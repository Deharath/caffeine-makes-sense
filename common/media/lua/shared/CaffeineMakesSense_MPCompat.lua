CaffeineMakesSense = CaffeineMakesSense or {}

CaffeineMakesSense.MP = CaffeineMakesSense.MP or {}
local MP = CaffeineMakesSense.MP

MP.NET_MODULE = "CaffeineMakesSenseRuntime"
MP.CAFFEINE_DOSE_COMMAND = "caffeine_dose"
MP.RESET_COMMAND = "reset"
MP.SET_FATIGUE_COMMAND = "set_fatigue"
MP.SNAPSHOT_COMMAND = "snapshot"
MP.REQUEST_SNAPSHOT_COMMAND = "request_snapshot"
MP.SLEEP_SESSION_COMMAND = "sleep_session"
MP.MOD_STATE_KEY = "CaffeineMakesSenseState"
MP.SCRIPT_VERSION = "1.0.5"

return MP
