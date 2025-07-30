#!/bin/bash

#==================================================================================================
# SCRIPT: check-k8s-services.sh
# DESCRIZIONE: Questo script esegue la scansione dei pod problematici in un cluster Kubernetes
#              (CrashLoopBackOff, ImagePullBackOff, ErrImagePull o riavvii eccessivi)
#              e propone azioni di remediation automatiche in modalità dry-run o le esegue
#              in modalità effettiva.
#
# UTILIZZO:
#   ./check-k8s-services.sh [-d] [-v]
#
# OPZIONI:
#   -d : Modalità Dry Run. Lo script identificherà le azioni da intraprendere ma non eseguirà
#        alcuna modifica sul cluster. È la modalità predefinita se non viene specificata
#        alcuna opzione.
#   -v : Modalità Verbose. Mostra tutti i log di debug, warn e info durante l'esecuzione,
#        oltre al report finale. Utile per il troubleshooting.
#
# AZIONI DI REMEDIATION:
#   - Deployment: Tenta un 'kubectl rollout undo deployment' per i pod problematici associati
#     a ReplicaSet attivi che sono gestiti da un Deployment.
#   - StatefulSet: Scala lo StatefulSet a 0 repliche per i pod problematici.
#   - Pods Residui/Orfani: Elimina i pod che non sono associati a un controller riconosciuto
#     (Deployment, StatefulSet, DaemonSet, Job, CronJob) o a un ReplicaSet non attivo.
#
# ESCLUSIONI:
#   - Namespace: I namespace specificati in 'excluded_namespaces' verranno ignorati.
#   - Tipi di Owner: I pod gestiti da DaemonSet, Job o CronJob verranno segnalati ma non
#     verranno intraprese azioni automatiche, a causa della loro natura e delle diverse
#     strategie di remediation richieste.
#
# REQUISITI:
#   - kubectl configurato per accedere al cluster target.
#   - jq installato.
#==================================================================================================

### CONFIGURAZIONE KUBECTL ###
export HOME="/home/gomiero1/"
export MKE_CLUSTER='NOPROD'
export BUNDLE_PATH="${HOME}/BUNDLES/${MKE_CLUSTER}"
export KUBECONFIG=${BUNDLE_PATH}/kube.yml

# Namespace da escludere dalla scansione e dal report finale dei pod problematici.
excluded_namespaces=("consul" "instana-agent" "kube" "node-feature-discovery" "msr" "kyverno" "monitoring" "logging" "ingress" "adc-ingress" "vault" "kube-state-metrics")
dry_run=true  # Imposta dry_run a true per default
verbose_mode=false
rolled_back_deployments=()
scaled_down_statefulsets=() # Lista per gli StatefulSet scalati a 0
deleted_pods=()
excluded_problematic_pods=()

# Soglia per riavvii eccessivi.
RESTART_THRESHOLD=100

# Funzione per il logging
# Questa funzione stampa i messaggi SOLO se verbose_mode è true.
# Altrimenti, i messaggi intermedi vengono soppressi.
# I messaggi di avvio e il riepilogo finale vengono stampati direttamente con 'echo'.
log() {
  local level="$1"
  local message="$2"
  if [[ "$verbose_mode" == true ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
  fi
}

# Parsing delle opzioni
while getopts "dv" opt; do
  case $opt in
    d)
      dry_run=true
      ;;
    v)
      verbose_mode=true
      ;;
    *)
      # L'uso non corretto stampa un errore e le istruzioni, bypassando 'log'
      echo "$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Utilizzo: $0 [-d] [-v)"
      exit 1
      ;;
  esac
done

# Sposta l'indice degli argomenti dopo l'elaborazione delle opzioni
shift $((OPTIND-1))


# Messaggio iniziale che indica la modalità di esecuzione - QUESTO È SEMPRE STAMPATO
echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Script avviato in modalità: $(if $dry_run; then echo "DRY RUN (nessuna modifica)"; else echo "EFFETTIVA (le modifiche verranno applicate)"; fi)"

start_time=$(date +%s)

# Verifica se kubectl è configurato - QUESTO È SEMPRE STAMPATO IN CASO DI ERRORE
if ! kubectl cluster-info &> /dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Impossibile connettersi al cluster Kubernetes. Assicurati che KUBECONFIG sia corretto e il cluster sia accessibile."
    exit 1
fi

# Crea un file temporaneo per l'output di jq
TEMP_POD_DATA=$(mktemp)

# Ottiene tutti i pod in CrashLoopBackOff, ImagePullBackOff, ErrImagePull O con riavvii eccessivi.
# Vengono estratti: namespace, nome del pod, il nome dell'owner primario e il tipo dell'owner.
# L'output viene reindirizzato al file temporaneo.
kubectl get pods --all-namespaces -o json | \
jq -r --argjson threshold "$RESTART_THRESHOLD" '
.items[] |
  # Filtra i pod che sono in stato Running, Pending o Unknown.
  select(.status.phase == "Running" or .status.phase == "Pending" or .status.phase == "Unknown") |
  # Ora, controlla se _qualsiasi_ container ha una delle condizioni problematiche.
  select(
    .status.containerStatuses | any(
      (.state.waiting.reason == "CrashLoopBackOff" or .state.waiting.reason == "ImagePullBackOff" or .state.waiting.reason == "ErrImagePull") or
      (.restartCount > $threshold)
    )
  ) |
  # Estrai il nome e il tipo dell_owner, con priorità: StatefulSet > ReplicaSet > DaemonSet > Job > CronJob.
  "\(.metadata.namespace) \(.metadata.name) " +
  (
    (.metadata.ownerReferences[]? | select(.kind == "StatefulSet") | .name) //
    (.metadata.ownerReferences[]? | select(.kind == "ReplicaSet") | .name) //
    (.metadata.ownerReferences[]? | select(.kind == "DaemonSet") | .name) //
    (.metadata.ownerReferences[]? | select(.kind == "Job") | .name) //
    (.metadata.ownerReferences[]? | select(.kind == "CronJob") | .name) //
    ""
  ) + " " +
  (
    (.metadata.ownerReferences[]? | select(.kind == "StatefulSet") | .kind) //
    (.metadata.ownerReferences[]? | select(.kind == "ReplicaSet") | .kind) //
    (.metadata.ownerReferences[]? | select(.kind == "DaemonSet") | .kind) //
    (.metadata.ownerReferences[]? | select(.kind == "Job") | .kind) //
    (.metadata.ownerReferences[]? | select(.kind == "CronJob") | .kind) //
    ""
  )
' > "$TEMP_POD_DATA"

# Legge il file temporaneo nella shell principale.
while read -r namespace pod_name owner_name owner_type; do

  # Controlliamo se il namespace è tra quelli esclusi PRIMA di fare ulteriori controlli
  is_excluded=false
  for excluded_ns in "${excluded_namespaces[@]}"; do
    if [[ "$namespace" == "$excluded_ns" ]]; then
      log "DEBUG" "Pod '$pod_name' nel namespace '$namespace' ignorato (namespace escluso)."
      excluded_problematic_pods+=("$namespace/$pod_name - Causa: Namespace escluso")
      continue 2 # Passa al prossimo pod nella while loop
    fi
  done

  # Logica di remediation basata sul tipo di owner
  case "$owner_type" in
    "ReplicaSet")
      replicaset_details_json=$(kubectl get replicaset "$owner_name" -n "$namespace" -o json 2>/dev/null)
      if [[ -z "$replicaset_details_json" ]]; then
          log "DEBUG" "Dettagli ReplicaSet '$owner_name' nel namespace '$namespace' non trovati. Saltato."
          excluded_problematic_pods+=("$namespace/$pod_name - Causa: Dettagli ReplicaSet non trovati")
          continue
      fi

      deployment_name=$(echo "$replicaset_details_json" | jq -r '.metadata.ownerReferences[]? | select(.kind == "Deployment").name // ""')
      if [[ -z "$deployment_name" ]]; then
        log "DEBUG" "ReplicaSet '$owner_name' nel namespace '$namespace' non ha un Deployment come owner. Considerato come pod residuo problematico."
        log "WARN" "Pod '$pod_name' nel namespace '$namespace' identificato come residuo problematico (appartiene a ReplicaSet '$owner_name' senza Deployment owner)."
        if $dry_run; then
          log "INFO" "[Dry-run] Avrebbe eliminato il pod residuo: $pod_name nel namespace $namespace."
          deleted_pods+=("$namespace/$pod_name")
        else
          log "INFO" "Tentativo di eliminazione del pod residuo: $pod_name nel namespace $namespace..."
          if kubectl delete pod "$pod_name" -n "$namespace"; then
            deleted_pods+=("$namespace/$pod_name")
            log "INFO" "Pod residuo '$pod_name' nel namespace '$namespace' eliminato con successo."
          else
            log "ERROR" "Errore durante l'eliminazione del pod residuo '$pod_name' nel namespace '$namespace'."
          fi
        fi
        continue
      fi

      deployment_json=$(kubectl get deployment "$deployment_name" -n "$namespace" -o json 2>/dev/null)
      if [[ -z "$deployment_json" ]]; then
          log "ERROR" "Impossibile recuperare i dettagli del deployment '$deployment_name' nel namespace '$namespace'. Saltato."
          excluded_problematic_pods+=("$namespace/$pod_name - Causa: Dettagli Deployment non trovati")
          continue
      fi

      desired_deployment_replicas=$(echo "$deployment_json" | jq -r '.spec.replicas // 0')
      current_rs_replicas=$(echo "$replicaset_details_json" | jq -r '.spec.replicas // 0')
      is_active_replicaset=false
      if [[ "$current_rs_replicas" -gt 0 ]]; then
          is_active_replicaset=true
      fi

      if $is_active_replicaset; then
        if printf '%s\n' "${rolled_back_deployments[@]}" | grep -q "^${namespace}/${deployment_name}$"; then
          log "DEBUG" "Deployment '$deployment_name' nel namespace '$namespace' già processato (rollback tentato). Saltato."
          continue
        fi

        if [[ "$desired_deployment_replicas" -gt 0 && "$current_rs_replicas" -gt 0 ]]; then
          log "WARN" "Deployment '$deployment_name' nel namespace '$namespace' identificato per ROLLBACK (ReplicaSet attivo '$owner_name' con pod '$pod_name' problematico)."
          if $dry_run; then
            log "INFO" "[Dry-run] Avrebbe tentato il rollback per deployment '$deployment_name' nel namespace '$namespace'."
            rolled_back_deployments+=("$namespace/$deployment_name")
          else
            log "INFO" "Tentativo di rollback per il deployment '$deployment_name' nel namespace '$namespace'..."
            if kubectl rollout undo deployment "$deployment_name" -n "$namespace"; then
              rolled_back_deployments+=("$namespace/$deployment_name")
              log "INFO" "Rollback di '$deployment_name' nel namespace '$namespace' avviato con successo."
            else
              log "ERROR" "Errore durante il rollback del deployment '$deployment_name' nel namespace '$namespace'."
            fi
          fi
        else
          log "DEBUG" "Deployment '$deployment_name' nel namespace '$namespace' (ReplicaSet attivo). Condizione di rollback non soddisfatta (desired/current replicas = 0). Skipping pod '$pod_name'."
          excluded_problematic_pods+=("$namespace/$pod_name - Causa: Rollback non applicabile (desired/current replicas = 0)")
        fi
      else
        log "WARN" "Pod '$pod_name' nel namespace '$namespace' identificato come residuo problematico (appartiene a ReplicaSet '$owner_name' non attivo)."
        if $dry_run; then
          log "INFO" "[Dry-run] Avrebbe eliminato il pod residuo: $pod_name nel namespace $namespace."
          deleted_pods+=("$namespace/$pod_name")
        else
          log "INFO" "Tentativo di eliminazione del pod residuo: $pod_name nel namespace $namespace..."
          if kubectl delete pod "$pod_name" -n "$namespace"; then
            deleted_pods+=("$namespace/$pod_name")
            log "INFO" "Pod residuo '$pod_name' nel namespace '$namespace' eliminato con successo."
          else
            log "ERROR" "Errore durante l'eliminazione del pod residuo '$pod_name' nel namespace '$namespace'."
          fi
        fi
      fi
      ;;

    "StatefulSet")
      # Logica specifica per StatefulSet: scala a 0 repliche.
      if printf '%s\n' "${scaled_down_statefulsets[@]}" | grep -q "^${namespace}/${owner_name}$"; then
        log "DEBUG" "StatefulSet '$owner_name' nel namespace '$namespace' già processato (scalatura a 0 tentata). Saltato."
        continue
      fi

      statefulset_json=$(kubectl get statefulset "$owner_name" -n "$namespace" -o json 2>/dev/null)
      if [[ -z "$statefulset_json" ]]; then
          log "ERROR" "Impossibile recuperare i dettagli dello StatefulSet '$owner_name' nel namespace '$namespace'. Saltato."
          excluded_problematic_pods+=("$namespace/$pod_name - Causa: Dettagli StatefulSet non trovati")
          continue
      fi

      log "WARN" "StatefulSet '$owner_name' nel namespace '$namespace' identificato per SCALATURA A 0 (pod '$pod_name' problematico)."
      if $dry_run; then
        log "INFO" "[Dry-run] Avrebbe scalato lo StatefulSet '$owner_name' nel namespace '$namespace' a 0 repliche."
        scaled_down_statefulsets+=("$namespace/$owner_name")
      else
        log "INFO" "Tentativo di scalatura dello StatefulSet '$owner_name' nel namespace '$namespace' a 0 repliche..."
        if kubectl scale statefulset "$owner_name" -n "$namespace" --replicas=0; then
          scaled_down_statefulsets+=("$namespace/$owner_name")
          log "INFO" "StatefulSet '$owner_name' scalato a 0 repliche con successo."
        else
          log "ERROR" "Errore durante la scalatura dello StatefulSet '$owner_name' nel namespace '$namespace' a 0 repliche."
        fi
      fi
      ;;

    "DaemonSet" | "Job" | "CronJob")
      # Per questi tipi di controller, non si esegue un rollback diretto sul pod.
      # La remediation dovrebbe avvenire sul controller stesso (es. scalare giù, aggiornare immagine).
      # Qui, semplicemente lo segnaliamo come escluso.
      log "INFO" "Pod '$pod_name' nel namespace '$namespace' è problematico ma gestito da un '$owner_type' ('$owner_name'). Non viene eseguita alcuna azione automatica. Considerato escluso dalla remediation."
      excluded_problematic_pods+=("$namespace/$pod_name - Causa: Gestito da $owner_type ($owner_name), remediation non automatica")
      ;;

    "")
      # Pod senza ownerReferences o con owner non riconosciuto. Consideralo un pod residuo da eliminare.
      log "WARN" "Pod '$pod_name' nel namespace '$namespace' identificato come pod residuo/orfano problematico (nessun owner riconosciuto)."
      if $dry_run; then
        log "INFO" "[Dry-run] Avrebbe eliminato il pod residuo/orfano: $pod_name nel namespace $namespace."
        deleted_pods+=("$namespace/$pod_name")
      else
        log "INFO" "Tentativo di eliminazione del pod residuo/orfano: $pod_name nel namespace $namespace..."
        if kubectl delete pod "$pod_name" -n "$namespace"; then
          deleted_pods+=("$namespace/$pod_name")
          log "INFO" "Pod residuo/orfano '$pod_name' nel namespace '$namespace' eliminato con successo."
        else
          log "ERROR" "Errore durante l'eliminazione del pod residuo/orfano '$pod_name' nel namespace '$namespace'."
        fi
      fi
      ;;

    *)
      # Qualsiasi altro tipo di owner non esplicitamente gestito
      log "INFO" "Pod '$pod_name' nel namespace '$namespace' è problematico e gestito da un tipo di owner non gestito ('$owner_type' - '$owner_name'). Non viene eseguita alcuna azione automatica. Considerato escluso dalla remediation."
      excluded_problematic_pods+=("$namespace/$pod_name - Causa: Tipo di owner non gestito ($owner_type)")
      ;;
  esac
done < "$TEMP_POD_DATA" # Reindirizza l'input dal file temporaneo

# Pulisci il file temporaneo
rm "$TEMP_POD_DATA"

## Riepilogo Esecuzione Script

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo # Aggiungo una riga vuota per separare il log iniziale dal riepilogo
echo "--- Riepilogo Esecuzione Script ---"
echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Tempo totale impiegato: $elapsed_time secondi."

if [ ${#rolled_back_deployments[@]} -gt 0 ]; then
  echo "--- Riepilogo Rollbacks Deployment ---"
  if $dry_run; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Deployments che *sarebbero stati* rollbackati in modalità non Dry Run:"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Deployments su cui è stato tentato il rollback:"
  fi
  for deployment in "${rolled_back_deployments[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO]   - $deployment"
  done
else
  echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Nessun deployment ha richiesto un rollback."
fi

if [ ${#scaled_down_statefulsets[@]} -gt 0 ]; then
  echo "--- Riepilogo Scalatura StatefulSet a 0 ---"
  if $dry_run; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] StatefulSet che *sarebbero stati* scalati a 0 repliche in modalità non Dry Run:"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] StatefulSet su cui è stata tentata la scalatura a 0 repliche:"
  fi
  for sfs in "${scaled_down_statefulsets[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO]   - $sfs"
  done
else
  echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Nessun StatefulSet ha richiesto una scalatura a 0."
fi

if [ ${#deleted_pods[@]} -gt 0 ]; then
  echo "--- Riepilogo Pods Eliminati (Residui/Orfani) ---"
  if $dry_run; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Pods residui che *sarebbero stati* eliminati in modalità non Dry Run:"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Pods residui eliminati:"
  fi
  for pod in "${deleted_pods[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO]   - $pod"
  done
else
  echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Nessun pod residuo eliminato."
fi

# Riepilogo Pods Problematici Esclusi
if [ ${#excluded_problematic_pods[@]} -gt 0 ]; then
  echo "--- Riepilogo Pods Problematici Esclusi dalla Remediation ---"
  echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] I seguenti pod sono stati identificati come problematici (per CrashLoopBackOff, ImagePullBackOff, ErrImagePull o riavvii > ${RESTART_THRESHOLD}) ma non sono stati processati a causa delle regole di esclusione o del tipo di controller:"
  for pod_info in "${excluded_problematic_pods[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO]   - $pod_info"
  done
else
  echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Nessun pod problematico è stato escluso dalla remediation."
fi

echo "$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Scansione completata."