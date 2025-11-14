#!/bin/bash

on_after_start() {
    log INFO "[plugin:test] Vault ha completato il start (hook: on_after_start)"
}

on_before_reset() {
    log INFO "[plugin:test] Hook prima del reset eseguito!"
}