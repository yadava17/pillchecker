// lib/constants/prefs_keys.dart

// Notification settings
const String kNotifModeKey = 'notif_mode_v1';              // 'standard' | 'basic' | 'off'
const String kEarlyLeadMinKey = 'notif_early_lead_min_v1'; // int minutes (0..240)
const String kLateAfterMinKey = 'notif_late_after_min_v1'; // int minutes (0..240)
const String kLastCycleStartKey = 'last_cycle_start_iso';
// Supply tracking settings
const String kSupplyModeKey = 'supply_mode_v1';           // 'decide' | 'on' | 'off'
const String kSupplyLowThresholdKey = 'supply_low_v1';    // int (1..999), default 10