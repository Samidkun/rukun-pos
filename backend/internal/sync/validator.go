package sync

import (
	"bytes"
	"encoding/json"
	"errors"

	"rukun.pos/backend/internal/store"
)

var (
	ErrNilRequest        = errors.New("request body cannot be nil")
	ErrMissingTerminalID = errors.New("terminal_id is required")
	ErrMissingDeviceID   = errors.New("device_id is required")
	ErrEmptyEvents       = errors.New("events list cannot be empty")
	ErrNilEvent          = errors.New("event cannot be nil")
	ErrMissingEventID    = errors.New("event_id is required")
	ErrMissingEntityType = errors.New("entity_type is required")
	ErrMissingOp         = errors.New("op is required")
	ErrEmptyPayload      = errors.New("payload cannot be empty")
	ErrInvalidPayload    = errors.New("payload must be valid JSON")
)

// ValidatePushRequest validates the push envelope structure.
func ValidatePushRequest(req *store.SyncPushRequest) error {
	if req == nil {
		return ErrNilRequest
	}
	if req.TerminalID == "" {
		return ErrMissingTerminalID
	}
	if req.DeviceID == "" {
		return ErrMissingDeviceID
	}
	if len(req.Events) == 0 {
		return ErrEmptyEvents
	}
	return nil
}

// ValidateEvent validates essential fields of a single sync event.
func ValidateEvent(evt *store.Event) error {
	if evt == nil {
		return ErrNilEvent
	}
	if evt.EventID == "" {
		return ErrMissingEventID
	}
	if evt.EntityType == "" {
		return ErrMissingEntityType
	}
	if evt.Op == "" {
		return ErrMissingOp
	}
	if len(evt.Payload) == 0 {
		return ErrEmptyPayload
	}

	trimmed := bytes.TrimSpace(evt.Payload)
	if len(trimmed) == 0 || string(trimmed) == "null" || string(trimmed) == "{}" {
		return ErrEmptyPayload
	}

	if !json.Valid(trimmed) {
		return ErrInvalidPayload
	}

	return nil
}
