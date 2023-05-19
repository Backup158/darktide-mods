--[[
    title: quick_chat
    author: Zombine
    date: 19/05/2023
    version: 1.1.0
]]
local mod = get_mod("quick_chat")
local ChatManagerConstants = require("scripts/foundation/managers/chat/chat_manager_constants")
local UISettings = require("scripts/settings/ui/ui_settings")

mod:io_dofile("quick_chat/scripts/mods/quick_chat/quick_chat_debug")

mod._memory = mod:persistent_table("quick_chat")

for _, setting in ipairs(mod._messages) do
    local id = setting.id

    mod["trigger_" .. id] = function()
        local ui_manager = Managers.ui

        if not ui_manager:chat_using_input() and
           not ui_manager:view_active("dmf_options_view") and
           not ui_manager:view_active("options_view") then
            mod.send_preset_message(id, "hotkey")
        end
    end
end

mod._get_message_by_id = function(id)
    for _, setting in ipairs(mod._messages) do
        if setting.id == id then
            return setting.message
        end
    end
end

mod._replace_place_holder = function(message, character_name, color)
    if not character_name then
        local player = Managers.player:local_player(1)
        character_name = player:name()
    end

    if color then
        character_name = string.format("{#color(%s,%s,%s)}%s{#reset()}", color[2], color[3], color[4], character_name)
    end

    if character_name then
        message = string.gsub(message, "%[name%]", character_name)
    end


    return message
end

mod.send_preset_message = function(id, message_type, character_name, color)
    local cooldown = mod._cooldown[message_type]
    local t = Managers.time:time("main")
    local latest_t = mod._latest_t[message_type]
    local message = mod._get_message_by_id(id)
    local channel_handle = mod._memory.channel_handle
    local check_mode = mod:get("enable_check_mode")

    if not t or
       not message or
       #message == 0 or
       not check_mode and not channel_handle or
       cooldown and latest_t and t - latest_t < cooldown then
        return
    end

    if cooldown ~= 0 then
        mod._latest_t[message_type] = t
    end

    message = mod._replace_place_holder(message, character_name, color)

    if check_mode then
        mod:echo(message)
    else
        Managers.chat:send_channel_message(channel_handle, message)
    end
end

local get_channel_handle = function(self)
    mod._memory.channel_handle = self._selected_channel_handle
end

mod:hook_safe("ConstantElementChat", "_on_disconnect_from_channel", get_channel_handle)
mod:hook_safe("ConstantElementChat", "_next_connected_channel_handle", get_channel_handle)

-- ##################################################
-- Events
-- ##################################################

local send_message_on_event = function(setting_id, message_type, character_name, color)
    local message_id = mod:get(setting_id)

    if not message_id or message_id == "none" then
        return
    end

    mod.debug.echo_kv("message", message_id)
    mod.send_preset_message(message_id, message_type, character_name, color)
end

-- player join

mod:hook_safe("ConstantElementChat", "cb_chat_manager_participant_added", function(self, channel_handle, participant)
    local channel = Managers.chat:sessions()[channel_handle]

    if channel.tag ~= ChatManagerConstants.ChannelTag.HUB and not participant.is_text_muted_for_me then
        send_message_on_event("auto_player_joined", "join", participant.displayname)
    end

end)

mod:hook_safe("ConstantElementChat", "_on_connect_to_channel", function(self, channel_handle)
    get_channel_handle(self)

    local channel = Managers.chat:sessions()[channel_handle]

    if channel.tag == ChatManagerConstants.ChannelTag.MISSION then
        send_message_on_event("auto_late_joined", "join")
    end
end)

-- Intro, Outro

mod:hook_safe("CinematicSceneExtension", "setup_from_component", function(self)
    local name = self._cinematic_name

    if string.match(name, "[io][nu]tro_") then
        if mod._cutscene_loaded[name] then
            if name == "intro_abc" then
                send_message_on_event("auto_mission_started", "cinematic")
            elseif name == "outro_win" then
                send_message_on_event("auto_mission_completed", "cinematic")
            elseif name == "outro_fail" then
                send_message_on_event("auto_mission_failed", "cinematic")
            end
        else
            mod._cutscene_loaded[name] = true
        end
    end
end)

-- Tagged (self)

mod:hook_safe("HudElementSmartTagging", "_add_smart_tag_presentation", function(self, tag_instance)
    local target_unit = tag_instance:target_unit()
    local target_type = target_unit and Unit.get_data(target_unit, "smart_tag_target_type")

    mod.debug.echo_kv("target_type", target_type)

    if target_type ~= "pickup" then
        return
    end

    local parent = self._parent
    local player = parent:player()
    local tagger_player = tag_instance:tagger_player()
    local is_my_tag = tagger_player and tagger_player:unique_id() == player:unique_id()

    if not is_my_tag then
        return
    end

    local pickup_name = Unit.get_data(target_unit, "pickup_type")
    local event_id = "auto_tagged_" .. pickup_name
    local message_type = nil

    if pickup_name == "tome" or
       pickup_name == "grimoire" then
        message_type = "tag_book"
    elseif
       pickup_name == "medical_crate_pocketable" or
       pickup_name == "medical_crate_deployable" or
       pickup_name == "ammo_cache_pocketable" or
       pickup_name == "ammo_cache_deployable" then
        message_type = "tag_crate"
    end

    mod.debug.echo_kv("pickup_name", pickup_name)
    mod.debug.echo_kv("message_type", message_type)

    if message_type then
        send_message_on_event(event_id, message_type)
    end
end)

-- Deployed Crates

local is_local_player = function(player)
    return player == Managers.player:local_player(1)
end

local get_place_event = function(self, callback)
    local player = self._player
    local is_myself = is_local_player(player)
    local action_settings = self._action_settings
    local unit_template, message_type = callback(action_settings)

    if unit_template and message_type then
        local suffix = is_myself and "_self" or "_others"
        local event_id = "auto_deployed_" .. unit_template .. suffix
        local player_slot = player and player._slot and player:slot()
        local player_name = player:name()
        local slot_color = player_slot and UISettings.player_slot_colors[player_slot]

        mod.debug.echo_kv("message_type", message_type)
        mod.debug.echo_kv("event_id", event_id)

        send_message_on_event(event_id, message_type, player_name, slot_color)
    end
end

mod:hook_safe("ActionPlaceDeployable", "start", function(self) -- Medical Crates
    local function callback(action_settings)
        local deployable_settings = action_settings.deployable_settings
        local unit_template = deployable_settings and deployable_settings.unit_template
        local message_type = unit_template == "medical_crate_deployable" and "deploy_med"

        return unit_template, message_type
    end

    get_place_event(self, callback)
end)

mod:hook_safe("ActionPlacePickup", "start", function(self) -- Ammo Crates
    local function callback(action_settings)
        local unit_template = action_settings.kind == "place_pickup" and "ammo_cache_deployable"
        local message_type = unit_template and "deploy_ammo"

        return unit_template, message_type
    end

    get_place_event(self, callback)
end)

mod:hook_safe("Unit", "flow_event", function(unit, name) -- both (anyone)
    if name == "lua_deploy" then
        local event_id = "auto_deployed_:s:_others"
        local message_type = "deploy_"

        if Unit.has_data(unit, "pickup_type") then
            event_id = string.gsub(event_id, ":s:", Unit.get_data(unit, "pickup_type"))
            message_type = message_type .. "ammo"
        else
            event_id = string.gsub(event_id, ":s:", "medical_crate_deployable")
            message_type = message_type .. "med"
        end

        mod.debug.echo_kv("message_type", message_type)
        mod.debug.echo_kv("event_id", event_id)

        send_message_on_event(event_id, message_type)
    end
end)

-- ##################################################
-- Utilities
-- ##################################################

local _init = function()
    mod._cutscene_loaded = {}
    mod._latest_t = {}
end

mod.on_all_mods_loaded = function()
    _init()
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == "StateLoading" and status == "enter" then
        _init()
    end
end