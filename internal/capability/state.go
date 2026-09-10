package capability

import (
	"encoding/json"
	"math"
	"strconv"
	"strings"
)

type StateMapping struct {
	Endpoint   uint16
	Capability string
	Value      any
}

func FromMatterAttribute(productType, path string, value any) (StateMapping, bool) {
	endpoint, clusterID, attributeID, ok := parseAttributePath(path)
	if !ok || !Supports(productType, endpoint, capabilityFor(clusterID, attributeID)) {
		return StateMapping{}, false
	}

	capabilityID := capabilityFor(clusterID, attributeID)
	if capabilityID == "" {
		return StateMapping{}, false
	}

	normalized, ok := normalizeMatterValue(capabilityID, value)
	if !ok {
		return StateMapping{}, false
	}
	return StateMapping{Endpoint: endpoint, Capability: capabilityID, Value: normalized}, true
}

func capabilityFor(clusterID, attributeID uint32) string {
	if attributeID != 0 {
		return ""
	}
	switch clusterID {
	case 6: // OnOff.OnOff
		return OnOff
	case 8: // LevelControl.CurrentLevel
		return Level
	case 1026: // TemperatureMeasurement.MeasuredValue
		return Temperature
	case 1029: // RelativeHumidityMeasurement.MeasuredValue
		return Humidity
	case 1030: // OccupancySensing.Occupancy
		return Motion
	case 69: // BooleanState.StateValue
		return Contact
	default:
		return ""
	}
}

func normalizeMatterValue(capabilityID string, value any) (any, bool) {
	switch capabilityID {
	case OnOff, Contact:
		return boolValue(value)
	case Motion:
		number, ok := numberValue(value)
		if !ok {
			return nil, false
		}
		return number != 0, true
	case Level:
		number, ok := numberValue(value)
		if !ok || number < 0 || number > 254 {
			return nil, false
		}
		return int(math.Round(number * 100 / 254)), true
	case Temperature, Humidity:
		number, ok := numberValue(value)
		if !ok {
			return nil, false
		}
		return number / 100, true
	default:
		return nil, false
	}
}

func parseAttributePath(path string) (uint16, uint32, uint32, bool) {
	parts := strings.Split(strings.TrimSpace(path), "/")
	if len(parts) != 3 {
		return 0, 0, 0, false
	}
	endpoint, err := strconv.ParseUint(parts[0], 10, 16)
	if err != nil || endpoint == 0 {
		return 0, 0, 0, false
	}
	clusterID, err := strconv.ParseUint(parts[1], 10, 32)
	if err != nil {
		return 0, 0, 0, false
	}
	attributeID, err := strconv.ParseUint(parts[2], 10, 32)
	if err != nil {
		return 0, 0, 0, false
	}
	return uint16(endpoint), uint32(clusterID), uint32(attributeID), true
}

func numberValue(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		return typed, true
	case float32:
		return float64(typed), true
	case int:
		return float64(typed), true
	case int8:
		return float64(typed), true
	case int16:
		return float64(typed), true
	case int32:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case uint:
		return float64(typed), true
	case uint8:
		return float64(typed), true
	case uint16:
		return float64(typed), true
	case uint32:
		return float64(typed), true
	case uint64:
		return float64(typed), true
	case json.Number:
		parsed, err := typed.Float64()
		return parsed, err == nil
	default:
		return 0, false
	}
}

func boolValue(value any) (bool, bool) {
	if typed, ok := value.(bool); ok {
		return typed, true
	}
	number, ok := numberValue(value)
	if !ok {
		return false, false
	}
	return number != 0, true
}
