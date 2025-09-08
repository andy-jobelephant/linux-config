#!/bin/bash

# Wait for Bluetooth and PipeWire to fully initialize
sleep 8

CARD="bluez_card.C0_95_6D_A9_83_2B"
DEFAULT_PROFILE="headset-head-unit"


pactl set-card-profile "$CARD" "$DEFAULT_PROFILE"
