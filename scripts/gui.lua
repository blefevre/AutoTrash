local gui = require("__flib__.gui-beta")
local table =require("__flib__.table")

local mod_gui = require ("__core__.lualib.mod-gui")

local constants = require("constants")
local presets = require("scripts.presets")

local at_util = require("scripts.util")
local player_data = require("scripts.player-data")
local format_number = at_util.format_number
local item_prototype = at_util.item_prototype
local in_network = at_util.in_network
local get_non_equipment_network = at_util.get_non_equipment_network

local function clamp(v, min, max)
    return (v < min) and min or (v > max and max or v)
end

local function format_request(item_config)
    return (item_config.min and item_config.min >= 0) and item_config.min or (item_config.max and 0)
end

local function format_trash(item_config)
    return (item_config.max < constants.max_request) and format_number(item_config.max, true) or "∞"
end

local function tonumber_max(n)
    n = tonumber(n) or 0
    return (n > constants.max_request) and constants.max_request or n
end

local function gcd(a, b)
    if a == b then
        return a
    elseif a > b then
        return gcd(a - b, b)
    elseif b > a then
        return gcd(a, b-a)
    end
end

local function get_network_data(player)
    local character = player.character
    if not character then return end
    local network = get_non_equipment_network(character)
    local requester = character.get_logistic_point(defines.logistic_member_index.character_requester)
    if not (network and requester and network.valid and requester.valid) then
        return
    end
    local on_the_way = requester.targeted_items_deliver
    local available = network.get_contents()
    local item_count = player.get_main_inventory().get_contents()
    local cursor_stack = player.cursor_stack
    cursor_stack = (cursor_stack and cursor_stack.valid_for_read) and {[cursor_stack.name] = cursor_stack.count} or {}
    local get_inventory, inventory = player.get_inventory, defines.inventory
    local armor = get_inventory(inventory.character_armor).get_contents()
    local gun = get_inventory(inventory.character_guns).get_contents()
    local ammo = get_inventory(inventory.character_ammo).get_contents()

    return available, on_the_way, item_count, cursor_stack, armor, gun, ammo
end

local at_gui = {
    defines = {
        trash_above_requested = "trash_above_requested",
        trash_unrequested = "trash_unrequested",
        trash_network = "trash_network",
        pause_trash = "pause_trash",
        pause_requests = "pause_requests",
        network_button = "network_button",
        status_display = "status_display",
    },
}

local function import_presets(player, pdata, add_presets, stack)
    if stack and stack.valid_for_read then
        if stack.is_blueprint and stack.is_blueprint_setup() then
            local preset, cc_found = presets.import(stack.get_blueprint_entities(), stack.blueprint_icons)
            if cc_found then
                pdata.config_tmp = preset
                player.print({"string-import-successful", "AutoTrash configuration"})
                pdata.selected = false
                at_gui.adjust_slots(player, pdata)
                at_gui.update_buttons(pdata)
                at_gui.update_sliders(pdata)
                at_gui.mark_dirty(pdata)
                --named preset
                if stack.label and stack.label ~= "AutoTrash_configuration" then
                    local textfield = pdata.gui.main.preset_textfield
                    local preset_name = string.sub(stack.label, 11)
                    if add_presets and at_gui.add_preset(player, pdata, preset_name, preset) then
                        pdata.selected_presets = {[preset_name] = true}
                        at_gui.update_presets(pdata)
                    end
                    textfield.text = preset_name
                    player.clear_cursor()
                    textfield.focus()
                end
            else
                player.print({"", {"error-while-importing-string"}, " ", {"at-message.import-error"}})
            end
            return true
        elseif add_presets and stack.is_blueprint_book then
            local book_inventory = stack.get_inventory(defines.inventory.item_main)
            local any_cc = false
            for i = 1, #book_inventory do
                local bp = book_inventory[i]
                if bp.valid_for_read and bp.is_blueprint_setup() then
                    local config, cc = presets.import(bp.get_blueprint_entities(), bp.blueprint_icons)
                    if cc then
                        any_cc = true
                        at_gui.add_preset(player, pdata, bp.label, config)
                    end
                end
            end
            if any_cc then
                player.print({"string-import-successful", {"at-gui.presets"}})
                at_gui.update_presets(pdata)
            else
                player.print({"", {"error-while-importing-string"}, " ", {"at-message.import-error"}})
            end
            return true
        end
    end
    return false
end

at_gui.toggle_setting = {
    trash_above_requested = function(player, pdata)
        at_util.set_requests(player, pdata)
        return pdata.flags.trash_above_requested
    end,
    trash_unrequested = function(player, pdata)
        at_util.set_requests(player, pdata)
        return pdata.flags.trash_unrequested
    end,
    trash_network = function(player, pdata)
        if pdata.flags.trash_network and not next(pdata.networks) then
            player.print{"at-message.no-network-set"}
            pdata.flags.trash_network = false
            return false
        end
        if pdata.flags.trash_network and in_network(player, pdata) then
            at_util.unpause_trash(player, pdata)
            at_gui.update_main_button(player, pdata)
        end
        return pdata.flags.trash_network
    end,
    pause_trash = function(player, pdata)
        if pdata.flags.pause_trash then
            at_util.pause_trash(player, pdata)
        else
            at_util.unpause_trash(player, pdata)
        end
        at_gui.update_main_button(player, pdata)
        return pdata.flags.pause_trash
    end,
    pause_requests = function(player, pdata)
        if pdata.flags.pause_requests then
            at_util.pause_requests(player, pdata)
        else
            at_util.unpause_requests(player, pdata)
        end
        at_gui.update_main_button(player, pdata)
        at_gui.update_status_display(player, pdata)
        return pdata.flags.pause_requests
    end,
}

at_gui.templates = {
    slot_table = {
        main = function(btns, pdata)
            local ret = {type = "table", column_count = pdata.settings.columns, style = "at_filter_group_table",
                ref = {"main", "slot_table"},
                style_mods = {minimal_height = pdata.settings.rows * 40}, children = {}}
            for i=1, btns do
                ret.children[i] = at_gui.templates.slot_table.button(i, pdata)
            end
            return ret
        end,
        button = function(i, pdata)
            local style = (i == pdata.selected) and "yellow_slot_button" or "slot_button"
            local config = pdata.config_tmp.config[i]
            local req = config and format_number(format_request(config), true) or ""
            local trash = config and format_trash(config)
            return {type = "choose-elem-button", name = i, elem_mods = {elem_value = config and config.name, locked = config and i ~= pdata.selected},
                        elem_type = "item", style = style,
                        actions = {
                            on_click = {gui = "slots", action = "item_button_click"},
                            on_elem_changed = {gui = "slots", action = "item_button"}
                        },
                        children = {
                            {type = "label", style = "at_request_label_top", ignored_by_interaction = true, caption = req},
                            {type = "label", style = "at_request_label_bottom", ignored_by_interaction = true, caption = trash}
                        }
                    }
        end,
    },
    frame_action_button = function(params)
        local ret = {type = "sprite-button", style = "frame_action_button", mouse_button_filter={"left"}}
        for k, v in pairs(params) do
            ret[k] = v
        end
        return ret
    end,
    pushers = {
        horizontal = {type = "empty-widget", style_mods = {horizontally_stretchable = true}},
        vertical = {type = "empty-widget", style_mods = {vertically_stretchable = true}}
    },
    import_export_window = function(bp_string, mode)
        local caption = bp_string and {"gui.export-to-string"} or {"gui-blueprint-library.import-string"}
        local button_caption = bp_string and {"gui.close"} or {"gui-blueprint-library.import"}
        local button_handler = bp_string and "close_button" or "import_button"
        return {type = "frame", ref = {"window", "main"}, style = "inner_frame_in_outer_frame", direction = "vertical", children = {
                {type = "flow", ref = {"window", "titlebar"}, children = {
                    {type = "label", style = "frame_title", caption = caption, elem_mods = {ignored_by_interaction = true}},
                    {type = "empty-widget", style = "flib_titlebar_drag_handle", elem_mods = {ignored_by_interaction = true}},
                    at_gui.templates.frame_action_button{
                        actions = {on_click = {gui = "import", action = "close_button"}},
                        ref = {"close_button"},
                        sprite = "utility/close_white", hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black"
                    }
                }},
                {type = "text-box", text = bp_string, ref = {"window", "textbox"}, elem_mods = {word_wrap = true}, style_mods = {width = 400, height = 250}},
                {type = "flow", direction = "horizontal", children={
                        at_gui.templates.pushers.horizontal,
                        {type = "label", name = "mode", caption = mode, visible = false},
                        {type = "button", style = "dialog_button", caption = button_caption,
                            actions = {on_click = {gui = "import", action = button_handler}}
                        }
                }}
            }}
    end,

    settings = function(flags)
        return {type = "frame", style = "at_bordered_frame", direction = "vertical", ref = {"main", "trash_options"}, children = {
            {
                type = "checkbox",
                name = at_gui.defines.trash_above_requested,
                caption = {"at-gui.trash-above-requested"},
                state = flags.trash_above_requested,
                actions = {on_checked_state_changed = {gui = "settings", action = "toggle"}},

            },
            {
                type = "checkbox",
                name = at_gui.defines.trash_unrequested,
                caption = {"at-gui.trash-unrequested"},
                state = flags.trash_unrequested,
                actions = {on_checked_state_changed = {gui = "settings", action = "toggle"}},
            },
            {
                type = "checkbox",
                name = at_gui.defines.trash_network,
                caption = {"at-gui.trash-in-main-network"},
                state = flags.trash_network,
                actions = {on_checked_state_changed = {gui = "settings", action = "toggle"}},
            },
            {
                type = "checkbox",
                name = at_gui.defines.pause_trash,
                caption = {"at-gui.pause-trash"},
                tooltip = {"at-gui.tooltip-pause-trash"},
                state = flags.pause_trash,
                actions = {on_checked_state_changed = {gui = "settings", action = "toggle"}},
            },
            {
                type = "checkbox",
                name = at_gui.defines.pause_requests,
                caption = {"at-gui.pause-requests"},
                tooltip = {"at-gui.tooltip-pause-requests"},
                state = flags.pause_requests,
                actions = {on_checked_state_changed = {gui = "settings", action = "toggle"}},
            },
            {
                type = "checkbox",
                name = at_gui.defines.status_display,
                caption = {"at-gui.status-display"},
                state = flags.status_display_open,
                actions = {on_checked_state_changed = {gui = "settings", action = "toggle_status_display"}},
            },
            {
                type = "flow", style_mods = {vertical_align = "center"}, children = {
                    {type = "label", caption = "Main networks: "},
                    {type = "button", caption = "+", style = "tool_button",
                        tooltip = {"at-gui.tooltip-add-network"},
                        actions = {on_click = {gui = "settings", action = "add_network"}},
                    },
                    {type = "button", caption = "-", style = "tool_button",
                        tooltip = {"at-gui.tooltip-remove-network"},
                        actions = {on_click = {gui = "settings", action = "remove_network"}},
                    },
                    {type = "sprite-button", sprite = "utility/rename_icon_normal", style = "tool_button",
                        ref = {"main", "network_edit_button"},
                        actions = {on_click = {gui = "settings", action = "edit_networks"}},
                        tooltip = {"at-gui.tooltip-edit-networks"}
                    },
                }
            },
            at_gui.templates.pushers.horizontal
        }}
    end,

    preset = function(preset_name, pdata)
        local style = pdata.selected_presets[preset_name] and "at_preset_button_selected" or "at_preset_button"
        local rip_style = pdata.death_presets[preset_name] and "at_preset_button_small_selected" or "at_preset_button_small"
        return {type = "flow", direction = "horizontal", name = preset_name, children = {
            {type = "button", style = style, caption = preset_name, name = preset_name,
                actions = {on_click = {gui = "presets", action = "load"}},
            },
            {type = "sprite-button", style = rip_style, sprite = "autotrash_rip",
                tooltip = {"at-gui.tooltip-rip"},
                actions = {on_click = {gui = "presets", action = "change_death_preset"}},
            },
            {type = "sprite-button", style = "at_delete_preset", sprite = "utility/trash",
                actions = {on_click = {gui = "presets", action = "delete"}},
            }
        }}
    end,

    presets = function(pdata)
        local ret = {}
        local i = 1
        for name in pairs(pdata.presets) do
            ret[i] = at_gui.templates.preset(name, pdata)
            i = i + 1
        end
        return ret
    end,

    networks = function(pdata)
        local ret = {}
        local i = 1
        for id, network in pairs(pdata.networks) do
            if network and network.valid then
                ret[i] = {type = "flow", name = id, direction = "horizontal", style_mods = {vertical_align = "center"}, children = {
                    {type = "label", caption = {"", {"gui-logistic.network"}, " #" .. id}},
                    at_gui.templates.pushers.horizontal,
                    {type = "sprite-button", style = "tool_button", sprite = "utility/map",
                        actions = {on_click = {gui = "networks", action = "view"}},
                        tooltip = {"at-gui.tooltip-show-network"}
                    },
                    {type = "sprite-button", style = "tool_button", sprite = "utility/trash",
                        actions = {on_click = {gui = "networks", action = "remove"}},
                    }
                }}
                i = i + 1
            end
        end
        return ret
    end,
}

at_gui.handlers = {}

at_gui.handlers.main = {
    mod_gui_button = function(e)
        if e.button == defines.mouse_button_type.right then
            if e.control then
                at_gui.toggle_status_display(e.player, e.pdata)
            end
        elseif e.button == defines.mouse_button_type.left then
            at_gui.toggle(e.player, e.pdata)
        end
    end,
    pin_button = function(e)
        local pdata = e.pdata
        if pdata.flags.pinned then
            pdata.gui.main.titlebar.pin_button.style = "frame_action_button"
            pdata.flags.pinned = false
            pdata.gui.main.window.force_auto_center()
            e.player.opened = pdata.gui.main.window
        else
            pdata.gui.main.titlebar.pin_button.style = "flib_selected_frame_action_button"
            pdata.flags.pinned = true
            pdata.gui.main.window.auto_center = false
            e.player.opened = nil
        end
    end,
    close_button = function(e)
        at_gui.close(e.player, e.pdata)
    end,
    window = function(e)
        if not e.pdata.flags.pinned then
            at_gui.close(e.player, e.pdata)
        end
    end,
    apply_changes = function(e)
        local player = e.player
        local pdata = e.pdata

        local adjusted = player_data.check_config(player, pdata)
        pdata.config_new = table.deep_copy(pdata.config_tmp)
        pdata.dirty = false
        pdata.gui.main.reset_button.enabled = false
        at_util.set_requests(player, pdata)
        if pdata.settings.close_on_apply then
            at_gui.close(player, pdata)
        end
        if adjusted then
            at_gui.update_buttons(pdata)
        end
        at_gui.update_status_display(player, pdata)
    end,
    reset = function(e)
        local pdata = e.pdata
        if pdata.flags.dirty then
            pdata.config_tmp = table.deep_copy(pdata.config_new)
            e.element.enabled = false
            pdata.selected_presets = {}
            pdata.selected = false
            pdata.flags.dirty = false
            at_gui.adjust_slots(e.player, pdata)
            at_gui.update_buttons(pdata)
            at_gui.update_sliders(pdata)
            at_gui.update_presets(pdata)
        end
    end,
    export = function(e)
        local player = e.player
        local pdata = e.pdata
        local name
        if table_size(pdata.selected_presets) == 1 then
            name = "AutoTrash_" .. next(pdata.selected_presets)
        else
            name = "AutoTrash_configuration"
        end
        if table_size(pdata.config_tmp.config) == 0 then
            player.print({"at-message.no-config-set"})
            return
        end
        local text = presets.export(pdata.config_tmp, name)
        if e.shift then
            local stack = player.cursor_stack
            if stack.valid_for_read then
                player.print({"at-message.empty-cursor-needed"})
                return
            else
                if stack.import_stack(text) ~= 0 then
                    player.print({"failed-to-import-string", name})
                    return
                end
            end
        else
            at_gui.create_import_window(player, pdata, text, "single")
        end
    end,
    export_all = function(e)
        local player = e.player
        local pdata = e.pdata
        if not next(pdata.presets) then
            player.print{"at-message.no-presets-to-export"}
            return
        end
        local text = presets.export_all(pdata)
        if e.shift then
            local stack = player.cursor_stack
            if stack.valid_for_read then
                player.print{"at-message.empty-cursor-needed"}
                return
            else
                if stack.import_stack(text) ~= 0 then
                    player.print{"failed-to-import-string"}
                    return
                end
            end
        else
            at_gui.create_import_window(player, pdata, text, "all")
        end
    end,
    import = function(e)
        local player = e.player
        local pdata = e.pdata
        if not import_presets(player, pdata, false, player.cursor_stack) then
            at_gui.create_import_window(player, pdata, nil, "single")
        end
    end,
    import_all = function(e)
        local player = e.player
        local pdata = e.pdata
        if not import_presets(player, pdata, true, player.cursor_stack) then
            at_gui.create_import_window(player, pdata, nil, "all")
        end
    end,
    quick_actions = function(e)
        local pdata = e.pdata
        local element = e.element
        local index = element.selected_index
        if index == 1 then return end

        local config_tmp = pdata.config_tmp
        if index == 2 then
            for _, config in pairs(config_tmp.config) do
                config.min = 0
            end
            config_tmp.c_requests = 0
        elseif index == 3 then
            for _, config in pairs(config_tmp.config) do
                config.max = constants.max_request
            end
        elseif index == 4 then
            config_tmp.config = {}
            config_tmp.by_name = {}
            config_tmp.max_slot = 0
            config_tmp.c_requests = 0
            pdata.selected = false
            at_gui.adjust_slots(e.player, pdata)
        elseif index == 5 then
            for _, config in pairs(config_tmp.config) do
                if config.min > 0 then
                    config.max = config.min
                end
            end
        elseif index == 6 then
            local c = 0
            for _, config in pairs(config_tmp.config) do
                if config.max < constants.max_request then
                    config.min = config.max
                    c = config.min > 0 and c + 1 or c
                end
            end
            config_tmp.c_requests = c
        end
        element.selected_index = 1
        at_gui.mark_dirty(pdata)
        at_gui.update_sliders(pdata)
        at_gui.update_buttons(pdata)
    end
}
at_gui.handlers.slots = {
    item_button_click = function(e)
        local player = e.player
        local pdata = e.pdata
        local elem_value = e.element.elem_value
        local old_selected = pdata.selected
        local index = tonumber(e.element.name)
        if e.button == defines.mouse_button_type.right then
            if not elem_value then
                pdata.selected = false
                at_gui.update_button(pdata, old_selected, pdata.gui.main.slot_table.children[old_selected])
                at_gui.update_sliders(pdata)
                return
            end
            at_gui.clear_button(pdata, index, e.element)
            at_gui.adjust_slots(player, pdata)
        elseif e.button == defines.mouse_button_type.left then
            if e.shift then
                local config_tmp = pdata.config_tmp
                local cursor_ghost = player.cursor_ghost
                --pickup ghost
                if elem_value and not cursor_ghost and not player.cursor_stack.valid_for_read then
                    pdata.selected = index
                    player.cursor_ghost = elem_value
                --drop ghost
                elseif cursor_ghost and old_selected then
                    local old_config = config_tmp.config[old_selected]
                    if elem_value and old_config and cursor_ghost.name == old_config.name then
                        player_data.swap_configs(pdata, old_selected, index)
                        player.cursor_ghost = nil
                        pdata.selected = index
                        at_gui.mark_dirty(pdata)
                    end
                    if not old_config then
                        pdata.selected = false
                        old_selected = false
                        player.cursor_ghost = nil
                    end
                end
                at_gui.update_button(pdata, index, e.element)
                at_gui.update_button(pdata, old_selected)
                at_gui.adjust_slots(player, pdata)
                at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                at_gui.update_sliders(pdata)
            else
                if not elem_value or old_selected == index then return end
                if player.cursor_ghost then
                    local old_config = old_selected and pdata.config_tmp.config[old_selected]
                    -- "interrupted" click-drag, reset value
                    if elem_value and old_config and old_config.name == elem_value then
                        e.element.elem_value = nil
                        return
                    end
                end
                pdata.selected = index
                if old_selected then
                    local old = pdata.gui.main.slot_table.children[old_selected]
                    at_gui.update_button(pdata, old_selected, old)
                end
                at_gui.update_button(pdata, index, e.element)
                at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                at_gui.update_sliders(pdata)
            end
        end
    end,
    item_button = function(e)
        local player = e.player
        local pdata = e.pdata
        local old_selected = pdata.selected
        --dragging to an empty slot, on_gui_click raised later
        if player.cursor_ghost and old_selected then return end

        local elem_value = e.element.elem_value
        local index = tonumber(e.element.name)
        if elem_value then
            local config_tmp = pdata.config_tmp
            local item_config = config_tmp.config[index]
            if item_config and elem_value == item_config.name then return end
            local existing_config = config_tmp.by_name[elem_value]
            if existing_config and existing_config.slot ~= index then
                local i = existing_config.slot
                player.print({"cant-set-duplicate-request", item_prototype(elem_value).localised_name})
                pdata.selected = i
                at_gui.update_button(pdata, i, pdata.gui.main.slot_table.children[i])
                pdata.gui.main.config_rows.scroll_to_element(pdata.gui.main.slot_table.children[i], "top-third")
                if item_config then
                    e.element.elem_value = item_config.name
                else
                    e.element.elem_value = nil
                end
                at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
                at_gui.update_sliders(pdata)
                return
            end
            pdata.selected = index
            local request_amount = item_prototype(elem_value).default_request_amount
            local trash_amount = pdata.settings.trash_equals_requests and request_amount or constants.max_request
            player_data.add_config(pdata, elem_value, request_amount, trash_amount, index)

            at_gui.mark_dirty(pdata)
            at_gui.update_button(pdata, index, e.element)
            if old_selected then
                at_gui.update_button(pdata, old_selected, pdata.gui.main.slot_table.children[old_selected])
            end
            at_gui.adjust_slots(player, pdata)
            at_gui.update_button_styles(player, pdata)--TODO: only update changed buttons
            at_gui.update_sliders(pdata)
        else
            at_gui.clear_button(pdata, index, e.element)
            at_gui.adjust_slots(player, pdata)
        end
    end
}
at_gui.handlers.presets = {
    save = function(e)
        local player = e.player
        local pdata = e.pdata
        local textfield = pdata.gui.main.preset_textfield
        local name = textfield.text
        if at_gui.add_preset(player, pdata, name) then
            pdata.selected_presets = {[name] = true}
            at_gui.update_presets(pdata)
        else
            textfield.focus()
        end
    end,
    load = function(e)
        local player = e.player
        local pdata = e.pdata
        local name = e.element.caption
        if not e.shift and not e.control then
            pdata.selected_presets = {[name] = true}
            pdata.config_tmp = table.deep_copy(pdata.presets[name])
            pdata.selected = false
            pdata.gui.main.preset_textfield.text = name
        else
            local selected_presets = pdata.selected_presets
            if not selected_presets[name] then
                selected_presets[name] = true
            else
                selected_presets[name] = nil
            end
            local tmp = {config = {}, by_name = {}, max_slot = 0, c_requests = 0}
            for key, _ in pairs(selected_presets) do
                presets.merge(tmp, pdata.presets[key])
            end
            pdata.config_tmp = tmp
            pdata.selected = false
        end
        at_gui.adjust_slots(player, pdata)
        at_gui.update_buttons(pdata)
        at_gui.mark_dirty(pdata, true)
        at_gui.update_presets(pdata)
        at_gui.update_sliders(pdata)
    end,
    delete = function(e)
        local pdata = e.pdata
        local parent = e.element.parent
        local name = parent.name
        parent.destroy()
        pdata.selected_presets[name] = nil
        pdata.death_presets[name] = nil
        pdata.presets[name] = nil
        at_gui.update_presets(pdata)
    end,
    change_death_preset = function(e)
        local pdata = e.pdata
        local name = e.element.parent.name
        if not (e.shift or e.control) then
            pdata.death_presets = {[name] = true}
        else
            local selected_presets = pdata.death_presets
            if not selected_presets[name] then
                selected_presets[name] = true
            else
                selected_presets[name] = nil
            end
        end
        at_gui.update_presets(pdata)
    end,
    textfield = function(e)
        e.element.select_all()
    end
}
at_gui.handlers.sliders = {
    request = function(e)
        local pdata = e.pdata
        if not pdata.selected then return end
        at_gui.update_request_config(e.element.slider_value, pdata)
    end,
    request_text = function(e)
        local pdata = e.pdata
        if not pdata.selected then return end
        at_gui.update_request_config(tonumber_max(e.element.text), pdata, true)
    end,
    trash = function(e)
        local pdata = e.pdata
        if not pdata.selected then return end
        at_gui.update_trash_config(e.player, pdata, e.element.slider_value, "slider")
    end,
    trash_text = function(e)
        local pdata = e.pdata
        if not pdata.selected then return end
        at_gui.update_trash_config(e.player, pdata, tonumber_max(e.element.text), "text")
    end,
    trash_confirmed = function(e)
        local pdata = e.pdata
        if not pdata.selected then return end
        at_gui.update_trash_config(e.player, pdata, tonumber_max(e.element.text), "confirmed")
    end
}

at_gui.handlers.settings = {
    toggle = function(e)
        local pdata = e.pdata
        local player = e.player
        if not player.character then return end
        local name = e.element.name
        if at_gui.toggle_setting[name] then
            if player_data.import_when_empty(player, pdata) then
                at_gui.update_buttons(pdata)
            end
            pdata.flags[name] = e.element.state
            e.element.state = at_gui.toggle_setting[name](e.player, pdata)
        end
    end,
    toggle_status_display = function(e)
        e.element.state = at_gui.toggle_status_display(e.player, e.pdata)
    end,
    add_network = function(e)
        local player = e.player
        if not player.character then return end
        local pdata = e.pdata
        local new_network = at_util.get_network_entity(player)
        if new_network then
            local new_id = new_network.unit_number
            if pdata.networks[new_id] then
                player.print{"at-message.network-exists", new_id}
                return
            end
            local new_net = new_network.logistic_network
            for id, network in pairs(pdata.networks) do
                if network and network.valid then
                    if network.logistic_network == new_net then
                        player.print{"at-message.network-exists", id}
                        return
                    end
                else
                    pdata.networks[id] = nil
                end
            end
            pdata.networks[new_id] = new_network
            player.print{"at-message.added-network", new_id}
        else
            player.print{"at-message.not-in-network"}
        end
        at_gui.update_networks(player, pdata)
    end,
    remove_network = function(e)
        local player = e.player
        if not player.character then return end
        local pdata = e.pdata
        local current_network = at_util.get_network_entity(player)
        if current_network then
            local nid = current_network.unit_number
            if pdata.networks[nid] then
                pdata.networks[nid] = nil
                player.print{"at-message.removed-network", nid}
                at_gui.update_networks(player, pdata)
                return
            end
            local new_net = current_network.logistic_network
            for id, network in pairs(pdata.networks) do
                if network and network.valid then
                    if network.logistic_network == new_net then
                        pdata.networks[id] = nil
                        player.print{"at-message.removed-network", id}
                        return
                    end
                else
                    pdata.networks[id] = nil
                end
            end
        else
            player.print{"at-message.not-in-network"}
        end
        at_gui.update_networks(player, pdata)
    end,
    edit_networks = function(e)
        local pdata = e.pdata
        at_gui.update_networks(e.player, pdata)
        local visible = not pdata.gui.main.networks.visible
        e.element.style = visible and "at_selected_tool_button" or "tool_button"
        pdata.gui.main.networks.visible = visible
        pdata.gui.main.presets.visible = not visible
    end,
    selection_tool = function(e)
        local player = e.player
        local pdata = e.pdata
        local cursor_stack = player.cursor_stack
        if cursor_stack and cursor_stack.valid_for_read then
            player.clear_cursor()
        end
        if cursor_stack.set_stack{name = "autotrash-network-selection", count = 1} then
            local location = pdata.gui.main.window.location
            location.x = 50
            pdata.gui.main.window.location = location
        end
    end,
}
at_gui.handlers.networks = {
    view = function(e)
        local pdata = e.pdata
        local id = tonumber(e.element.parent.name)
        local entity = pdata.networks[id]
        if entity and entity.valid then
            e.player.zoom_to_world(entity.position, 0.3)
            local location = pdata.gui.main.window.location
            location.x = 50
            pdata.gui.main.window.location = location
        end
    end,
    remove = function(e)
        local pdata = e.pdata
        local flow = e.element.parent
        local id = tonumber(flow.name)
        if id then
            pdata.networks[id] = nil
        end
        flow.destroy()
    end
}
at_gui.handlers.import = {
    import_button = function(e)
        local player = e.player
        local pdata = e.pdata
        local add_presets = e.element.parent.mode.caption == "all"
        local inventory = game.create_inventory(1)

        inventory.insert{name = "blueprint"}
        local stack = inventory[1]
        local result = stack.import_stack(pdata.gui.import.window.textbox.text)
        if result ~= 0 then
            inventory.destroy()
            return result
        end
        result = import_presets(player, pdata, add_presets, stack)
        inventory.destroy()
        if not result then
            player.print({"failed-to-import-string", "Unknown error"})
        end
        at_gui.handlers.import.close_button.on_gui_click(e)
    end,
    close_button = function(e)
        local pdata = e.pdata
        pdata.gui.import.window.main.destroy()
        pdata.gui.import = nil
    end
}

function at_gui.update_request_config(number, pdata, from_text)
    local selected = pdata.selected
    local config_tmp = pdata.config_tmp
    local item_config = config_tmp.config[selected]
    if not from_text then
        number = number * item_prototype(item_config.name).stack_size
    end
    if item_config.min == 0 and number > 0 then
        config_tmp.c_requests = config_tmp.c_requests + 1
    end
    if item_config.min > 0 and number == 0 then
        config_tmp.c_requests = config_tmp.c_requests > 0 and config_tmp.c_requests - 1 or 0
    end
    item_config.min = number
    --prevent trash being set to a lower value than request to prevent infinite robo loop
    if item_config.max < constants.max_request and number > item_config.max then
        item_config.max = number
    end
    at_gui.mark_dirty(pdata)
    at_gui.update_sliders(pdata)
    at_gui.update_button(pdata, pdata.selected)
end

function at_gui.update_trash_config(player, pdata, number, source)
    local selected = pdata.selected
    local config_tmp = pdata.config_tmp
    local item_config = config_tmp.config[selected]
    if item_config then
        if source == "slider" then
            local stack_size = item_prototype(item_config.name).stack_size
            number = number < 10 and number * stack_size or constants.max_request
        end
        if source ~= "text" then
            if number < constants.max_request and item_config.min > number then
                if item_config.min > 0 and number == 0 then
                    config_tmp.c_requests = config_tmp.c_requests > 0 and config_tmp.c_requests - 1 or 0
                end
                item_config.min = number
                if source == "confirmed" then
                    player.print{"at-message.adjusted-trash-amount", at_util.item_prototype(item_config.name).localised_name, number}
                end
            end
        end
        item_config.max = number
        at_gui.mark_dirty(pdata)
        at_gui.update_button(pdata, pdata.selected)
    else
        at_gui.update_button(pdata, pdata.selected)
        pdata.selected = false
    end
    at_gui.update_sliders(pdata)
end

function at_gui.adjust_slots(player, pdata)
    local slot_table = pdata.gui.main.slot_table
    local old_slots = #slot_table.children
    local min_step = (10 * pdata.settings.columns) / gcd(10, pdata.settings.columns)
    local slots = math.ceil(pdata.config_tmp.max_slot / pdata.settings.columns) * min_step
    --increase if anything is set in the last row
    if (slots == pdata.config_tmp.max_slot) or (pdata.config_tmp.max_slot % min_step > 1) then
        slots = slots + min_step
    end
    slots = clamp(slots, 40, 65529)
    if old_slots == slots then return end

    local diff = slots - old_slots
    if diff > 0 then
        for i = old_slots+1, slots do
            gui.build(slot_table, {at_gui.templates.slot_table.button(i, pdata)})
        end
    elseif diff < 0 then
        for i = old_slots, slots+1, -1 do
            local btn = slot_table.children[i]
            btn.destroy()
        end
    end

    local width = pdata.settings.columns * 40
    width = (slots <= (pdata.settings.rows * pdata.settings.columns)) and width or (width + 12)
    pdata.gui.main.config_rows.style.width = width
    pdata.gui.main.config_rows.scroll_to_element(slot_table.children[slots])
end

function at_gui.update_buttons(pdata)
    if not pdata.flags.gui_open then return end
    local children = pdata.gui.main.slot_table.children
    for i=1, #children do
        at_gui.update_button(pdata, i, children[i])
    end
end

function at_gui.get_button_style(i, selected, item, available, on_the_way, item_count, cursor_stack, armor, gun, ammo, paused)
    if paused or not (available and on_the_way and item and item.min > 0) then
        return (i == selected) and "yellow_slot_button" or "slot_button"
    end
    if i == selected then
        return "yellow_slot_button"
    end
    local n = item.name
    local diff = item.min - ((item_count[n] or 0) + (armor[n] or 0) + (gun[n] or 0) + (ammo[n] or 0) + (cursor_stack[n] or 0))

    if diff <= 0 then
        return "slot_button"
    else
        local diff2 = diff - (on_the_way[n] or 0) - (available[n] or 0)
        if diff2 <= 0 then
            return "yellow_slot_button", diff
        elseif (on_the_way[n] and not available[n]) then
        --item.name == "locomotive" then
            return "blue_slot", diff
        end
        return "red_slot_button", diff
    end
end

function at_gui.update_button_styles(player, pdata)
    local ruleset_grid = pdata.gui.main.slot_table
    if not (ruleset_grid and ruleset_grid.valid) then return end
    local selected = pdata.selected
    local config = pdata.config_tmp
    local available, on_the_way, item_count, cursor_stack, armor, gun, ammo = get_network_data(player)
    if not (available and on_the_way and config.c_requests > 0 and not pdata.flags.pause_requests) then
        local children = ruleset_grid.children
        for i=1, #children do
            children[i].style = (i == selected) and "yellow_slot_button" or "slot_button"
        end
        return
    end
    config = config.config
    local ret = {}
    local buttons = ruleset_grid.children
    for i=1, #buttons do
        local item = config[i]
        local style, diff = at_gui.get_button_style(i, selected, config[i], available, on_the_way, item_count, cursor_stack, armor, gun, ammo)
        if item and item.min > 0 then
            ret[item.name] = {style, diff}
        end
        buttons[i].style = style
    end
    return ret
end

function at_gui.update_button(pdata, i, button)
    if not (button and button.valid) then
        if not i then return end
        button = pdata.gui.main.slot_table.children[i]
    end
    local req = pdata.config_tmp.config[i]
    if req then
        button.children[1].caption = format_number(format_request(req), true)
        button.children[2].caption = format_trash(req)
        button.elem_value = req.name
        button.locked = i ~= pdata.selected
    else
        button.children[1].caption = ""
        button.children[2].caption = ""
        button.elem_value = nil
        button.locked = false
    end
    button.style = (i == pdata.selected) and "yellow_slot_button" or "slot_button"
end

function at_gui.clear_button(pdata, index, button)
    player_data.clear_config(pdata, index)
    at_gui.mark_dirty(pdata)
    at_gui.update_button(pdata, index, button)
    at_gui.update_sliders(pdata)
end

function at_gui.update_sliders(pdata)
    if not pdata.flags.gui_open then return end
    if pdata.selected then
        local sliders = pdata.gui.main.sliders
        local item_config = pdata.config_tmp.config[pdata.selected]
        if item_config then
            local stack_size = item_prototype(item_config.name).stack_size
            sliders.request.slider_value = clamp(item_config.min / stack_size, 0, 10)
            sliders.request_text.text = tostring(format_request(item_config) or "0")

            sliders.trash.slider_value = clamp(item_config.max / stack_size, 0, 10)
            sliders.trash_text.text = tostring(item_config.max < constants.max_request and item_config.max or "inf.")
        end
    end
    local visible = pdata.selected and true or false
    for _, child in pairs(pdata.gui.main.sliders.table.children) do
        child.visible = visible
    end
end

function at_gui.add_preset(player, pdata, name, config)
    config = config or pdata.config_tmp
    if name == "" then
        player.print({"at-message.name-not-set"})
        return
    end
    if pdata.presets[name] then
        if not pdata.settings.overwrite then
            player.print({"at-message.name-in-use"})
            return
        end
        pdata.presets[name] = table.deep_copy(config)
        player.print({"at-message.preset-updated", name})
    else
        pdata.presets[name] = table.deep_copy(config)
        gui.build(pdata.gui.main.presets_flow, {at_gui.templates.preset(name, pdata)})
    end
    return true
end

function at_gui.update_presets(pdata)
    if not pdata.flags.gui_open then return end
    local children = pdata.gui.main.presets_flow.children
    local selected_presets = pdata.selected_presets
    local death_presets = pdata.death_presets
    for i=1, #children do
        local preset = children[i].children[1]
        local rip = children[i].children[2]
        local preset_name = preset.caption
        preset.style = selected_presets[preset_name] and "at_preset_button_selected" or "at_preset_button"
        rip.style = death_presets[preset_name] and "at_preset_button_small_selected" or "at_preset_button_small"
    end
    local s = table_size(selected_presets)
    if s == 1 then
        pdata.gui.main.preset_textfield.text = next(selected_presets)
    elseif s > 1 then
        pdata.gui.main.preset_textfield.text = ""
    end
end

function at_gui.update_networks(player, pdata)
    if not pdata.flags.gui_open then return end
    local networks = pdata.gui.main.networks_flow
    networks.clear()
    gui.build(networks, at_gui.templates.networks(pdata))
end

function at_gui.create_main_window(player, pdata)
    if not player.character then return end
    local flags = pdata.flags
    pdata.selected = false
    local cols = pdata.settings.columns
    local rows = pdata.settings.rows
    local btns = math.max(40, player.character.request_slot_count, pdata.config_tmp.max_slot)
    local width = cols * 40
    width = (btns <= (rows*cols)) and width or (width + 12)
    local max_height = (player.display_resolution.height / player.display_scale) * 0.97
    local max_width = (player.display_resolution.width / player.display_scale)
    local gui_data = gui.build(player.gui.screen,{
        {type = "frame", style = "outer_frame", style_mods = {maximal_width = max_width, maximal_height = max_height},
            actions = {on_closed = {gui = "main", action = "window"}},
            ref = {"main", "window"}, children = {
            {type = "frame", style = "inner_frame_in_outer_frame", direction = "vertical", children = {
                {type = "flow", ref = {"main", "titlebar", "flow"}, children = {
                    {type = "label", style = "frame_title", caption = {"mod-name.AutoTrash"}, elem_mods = {ignored_by_interaction = true}},
                    {type = "empty-widget", style = "flib_titlebar_drag_handle", elem_mods = {ignored_by_interaction = true}},
                    at_gui.templates.frame_action_button{sprite="at_pin_white", hovered_sprite="at_pin_black", clicked_sprite="at_pin_black",
                        actions = {on_click = {gui = "main", action = "pin_button"}},
                        ref = {"main", "titlebar", "pin_button"}, tooltip={"at-gui.keep-open"}},
                    at_gui.templates.frame_action_button{sprite = "utility/close_white", hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black",
                        actions = {on_click = {gui = "main", action = "close_button"}},
                        ref = {"main", "titlebar", "close_button"}
                    }
                }},
                {type = "flow", direction = "horizontal", style = "inset_frame_container_horizontal_flow", children = {
                    {type = "frame", style = "inside_shallow_frame", direction = "vertical", children = {
                        {type = "frame", style = "subheader_frame", children={
                            {type = "label", style = "subheader_caption_label", caption = {"at-gui.logistics-configuration"}},
                            at_gui.templates.pushers.horizontal,
                            {type = "sprite-button", style = "tool_button_green", style_mods = {padding = 0},
                                sprite = "utility/check_mark_white", tooltip = {"module-inserter-config-button-apply"},
                                actions = {on_click = {gui = "main", action = "apply_changes"}},
                            },
                            {type = "sprite-button", style = "tool_button_red", ref = {"main", "reset_button"}, sprite = "utility/reset_white",
                                actions = {on_click = {gui = "main", action = "reset"}},
                            },
                            {type = "sprite-button", style = "tool_button", sprite = "utility/export_slot", tooltip = {"at-gui.tooltip-export"},
                                actions = {on_click = {gui = "main", action = "export"}}
                            },
                            {type = "sprite-button", style = "tool_button", sprite = "at_import_string", tooltip = {"at-gui.tooltip-import"},
                                actions = {on_click = {gui = "main", action = "import"}},
                            }
                        }},
                        {type = "flow", direction="vertical", style_mods = {padding= 12, top_padding = 8, vertical_spacing = 10}, children = {
                            {type = "frame", style = "deep_frame_in_shallow_frame", children = {
                                {type = "scroll-pane", style = "at_slot_table_scroll_pane", name = "config_rows", ref = {"main", "config_rows"},
                                    style_mods = {
                                        width = width,
                                        height = pdata.settings.rows * 40
                                    },
                                    children = {
                                        at_gui.templates.slot_table.main(btns, pdata),
                                    }
                                }
                            }},
                            {type = "frame", style = "at_bordered_frame", direction = "vertical", children = {
                                {type = "table", ref = {"main", "sliders", "table"}, style_mods = {height = 60, horizontal_spacing = 8}, column_count = 3, children = {
                                    {type = "label", caption = {"at-gui.request"}},
                                    {type = "slider", ref = {"main", "sliders", "request"},
                                        minimum_value = 0, maximum_value = 10, style = "notched_slider",
                                        actions = {on_value_changed = {gui = "sliders", action = "request"}}
                                    },
                                    {type = "textfield", style = "slider_value_textfield",
                                        numeric = true, allow_negative = false, lose_focus_on_confirm = true,
                                        ref = {"main", "sliders", "request_text"},
                                        actions = {on_text_changed = {gui = "sliders", action = "request_text"}},
                                    },
                                    {type = "label", caption={"at-gui.trash"}},
                                    {type = "slider", ref = {"main", "sliders", "trash"}, style = "notched_slider",
                                        minimum_value = 0, maximum_value = 10,
                                        actions = {on_value_changed = {gui = "sliders", action = "trash"}},
                                    },
                                    {type = "textfield", style = "slider_value_textfield",
                                        numeric = true, allow_negative = false, lose_focus_on_confirm = true,
                                        ref = {"main", "sliders", "trash_text"},
                                        actions = {
                                            on_text_changed = {gui = "sliders", action = "trash_text"},
                                            on_confirmed = {gui = "sliders", action = "trash_confirmed"}
                                        },
                                    },
                                }},
                                {type = "drop-down", style = "at_quick_actions", tooltip = {"at-gui.tooltip-quick-actions"},
                                    actions = {on_selection_state_changed = {gui = "main", action = "quick_actions"}},
                                    items = constants.quick_actions,
                                    selected_index = 1,
                                },
                                at_gui.templates.pushers.horizontal
                            }},
                            at_gui.templates.settings(flags),
                        }},

                    }},
                    {type = "frame", ref = {"main", "presets"}, style = "inside_shallow_frame", direction = "vertical", children = {
                        {type = "frame", style = "subheader_frame", children={
                            {type = "label", style = "subheader_caption_label", caption = {"at-gui.presets"}},
                            at_gui.templates.pushers.horizontal,
                            {type = "sprite-button", style = "tool_button", sprite = "utility/export_slot", tooltip = {"at-gui.tooltip-export-all"},
                                actions = {on_click = {gui = "main", action = "export_all"}},
                            },
                            {type = "sprite-button", style = "tool_button", sprite = "at_import_string", tooltip = {"at-gui.tooltip-import-all"},
                                actions = {on_click = {gui = "main", action = "import_all"}},
                            },
                        }},
                        {type = "flow", direction="vertical", style = "at_right_container_flow", children = {
                            {type = "flow", children = {
                                {type = "textfield", style = "long_number_textfield", ref = {"main", "preset_textfield"},
                                    actions = {on_click = {gui = "presets", action = "textfield"}},
                                },
                                at_gui.templates.pushers.horizontal,
                                {type = "button", caption = {"gui-save-game.save"}, style = "at_save_button",
                                    actions = {on_click = {gui = "presets", action = "save"}}
                                }
                            }},
                            {type = "frame", style = "deep_frame_in_shallow_frame", children = {
                                {type = "scroll-pane", style = "at_right_scroll_pane", children = {
                                    {type = "flow", direction = "vertical", ref = {"main", "presets_flow"}, style = "at_right_flow_in_scroll_pane", children =
                                        at_gui.templates.presets(pdata),
                                    },
                                }}
                            }},
                        }}
                    }},
                    {type = "frame", ref = {"main", "networks"}, visible = false, style = "inside_shallow_frame", direction = "vertical", children = {
                        {type = "frame", style = "subheader_frame", children={
                            {type = "label", style = "subheader_caption_label", caption = {"gui-logistic.logistic-networks"}},
                            at_gui.templates.pushers.horizontal,
                            {type = "sprite-button", style = "tool_button", style_mods = {padding = 0},
                                actions = {on_click = {gui = "settings", action = "selection_tool"}},
                                sprite = "autotrash_selection", tooltip = {"at-gui.tooltip-selection-tool"}},
                        }},
                        {type = "flow", direction = "vertical", style = "at_right_container_flow", children = {
                            {type = "frame", style = "deep_frame_in_shallow_frame", children = {
                                {type = "scroll-pane", style = "at_right_scroll_pane", children = {
                                    {type = "flow", direction = "vertical", ref = {"main", "networks_flow"}, style = "at_right_flow_in_scroll_pane", children =
                                        at_gui.templates.networks(pdata),
                                    },
                                }}
                            }},
                        }}
                    }}
                }}
            }},
        }
    }})
    gui_data.main.titlebar.flow.drag_target = gui_data.main.window
    gui_data.main.window.force_auto_center()
    gui_data.main.window.visible = false

    pdata.gui.main = gui_data.main
    if pdata.flags.pinned then
        pdata.gui.main.titlebar.pin_button.style = "flib_selected_frame_action_button"
    end
    pdata.selected = false
end

function at_gui.create_import_window(player, pdata, bp_string, mode)
    if pdata.gui.import and pdata.gui.import.window and pdata.gui.import.window.main.valid then
        local window = pdata.gui.import.window.main
        window.destroy()
        pdata.gui.import = nil
    end
    local refs = gui.build(player.gui.screen, {at_gui.templates.import_export_window(bp_string, mode)})
    pdata.gui.import = refs
    local import_window = pdata.gui.import.window
    import_window.titlebar.drag_target = pdata.gui.import.window.main
    import_window.main.force_auto_center()
    local textbox = import_window.textbox
    if bp_string then
        textbox.read_only = true
    end
    textbox.select_all()
    textbox.focus()
end


function at_gui.init(player, pdata)
    at_gui.destroy(player, pdata)
    at_gui.update_main_button(player, pdata)
    at_gui.init_status_display(player, pdata)
end

function at_gui.init_main_button(player, pdata, destroy)
    local flow = mod_gui.get_button_flow(player)
    local visible = pdata.flags.can_open_gui and pdata.settings.show_button
    local button = flow.at_config_button
    button = (button and button.valid) and button
    if destroy and button then
        button.destroy()
        button = nil
    end
    if visible then
        if not button then
            local children = #flow.children
            local index = pdata.main_button_index
            if index and index > children then
                index = nil
            end
            local gui_data = gui.build(flow, {{type = "sprite-button", name = "at_config_button", style = mod_gui.button_style,
                actions = {on_click = {gui = "main", action = "mod_gui_button"}},
                ref = {"main_button"},
                index = index,
                sprite = "autotrash_trash", tooltip = {"at-gui.tooltip-main-button", pdata.flags.status_display_open and "On" or "Off"}
            }})
            pdata.gui.main_button = gui_data.main_button
        else
            pdata.gui.main_button = button
            gui.update_tags(button, {flib = {on_click = {gui = "main", action = "mod_gui_button"}}})
        end
        return button
    else
        if button then
            pdata.main_button_index = button.get_index_in_parent()
            local button_flow = button.parent
            button.destroy()
            pdata.gui.main_button = nil
            if #button_flow.children == 0 then
                button_flow.parent.destroy()
            end
        end
    end
end

function at_gui.init_status_display(player, pdata, keep_status)
    local status_flow = pdata.gui.status_flow
    if not (status_flow and status_flow.valid) then
        status_flow = mod_gui.get_frame_flow(player).autotrash_status_flow
        if not (status_flow and status_flow.valid) then
            status_flow = mod_gui.get_frame_flow(player).add{type = "flow", name = "autotrash_status_flow", direction = "vertical"}
        end
        pdata.gui.status_flow = status_flow
    end
    status_flow.clear()

    local visible = false
    if keep_status then
        visible = pdata.flags.can_open_gui and pdata.flags.status_display_open
    end
    status_flow.visible = visible
    pdata.flags.status_display_open = visible
    pdata.gui.status_table = nil

    local status_table = status_flow.add{
        type = "table",
        style = "at_request_status_table",
        column_count = pdata.settings.status_columns
    }
    pdata.gui.status_table = status_table

    for _ = 1, pdata.settings.status_count do
        status_table.add{
            type = "sprite-button",
            visible = false
        }
    end
    at_gui.update_settings(pdata)
    at_gui.update_status_display(player, pdata)
end

function at_gui.open_status_display(player, pdata)
    local status_table = pdata.gui.status_table
    if not (status_table and status_table.valid) then
        at_gui.init_status_display(player, pdata)
    end
    if pdata.flags.can_open_gui then
        status_table.parent.visible = true
        pdata.flags.status_display_open = true
        at_gui.update_main_button(player, pdata)
        at_gui.update_status_display(player, pdata)
    end
    at_gui.update_settings(pdata)
end

function at_gui.close_status_display(player, pdata)
    pdata.flags.status_display_open = false
    at_gui.update_settings(pdata)
    at_gui.update_main_button(player, pdata)
    local status_table = pdata.gui.status_table
    if not (status_table and status_table.valid) then
        return
    end
    status_table.parent.visible = false
end

function at_gui.toggle_status_display(player, pdata)
    if pdata.flags.status_display_open then
        at_gui.close_status_display(player, pdata)
        return false
    else
        at_gui.open_status_display(player, pdata)
        return true
    end
end

function at_gui.update_status_display(player, pdata)
    if not pdata.flags.status_display_open then return end
    local status_table = pdata.gui.status_table
    if not (status_table and status_table.valid) then
        at_gui.init_status_display(player, pdata)
    end
    local available, on_the_way, item_count, cursor_stack, armor, gun, ammo = get_network_data(player)
    if not (available and not pdata.flags.pause_requests) then
        for _, child in pairs(status_table.children) do
            child.visible = false
        end
        return true
    end

    local max_count = pdata.settings.status_count
    local get_request_slot = player.character.get_request_slot

    local children = status_table.children
    local c = 1
    for i = 1, player.character.request_slot_count do
        local item = get_request_slot(i)
        if item and item.count > 0 then
            if c > max_count then return true end
            item.min = item.count
            if item.min > 0 then
                local style, diff = at_gui.get_button_style(i, false, item, available, on_the_way, item_count, cursor_stack, armor, gun, ammo)
                if style ~= "slot_button" then
                    local button = children[c]
                    button.style = style
                    button.sprite = "item/" .. item.name
                    button.number = diff
                    button.visible = true
                    c = c + 1
                end
            end
        end
    end
    for i = c, max_count do
        children[i].visible = false
    end
    return true
end

function at_gui.update_main_button(player, pdata)
    local mainButton = at_gui.init_main_button(player, pdata)
    if not mainButton then return end
    local flags = pdata.flags
    if flags.pause_trash and not flags.pause_requests then
        mainButton.sprite = "autotrash_trash_paused"
    elseif flags.pause_requests and not flags.pause_trash then
        mainButton.sprite = "autotrash_requests_paused"
    elseif flags.pause_trash and flags.pause_requests then
        mainButton.sprite = "autotrash_both_paused"
    else
        mainButton.sprite = "autotrash_trash"
    end
    mainButton.tooltip = {"at-gui.tooltip-main-button", flags.status_display_open and "On" or "Off"}
    at_gui.update_settings(pdata)
end

function at_gui.update_settings(pdata)
    if not pdata.flags.gui_open then return end
    local frame = pdata.gui.main.trash_options
    if not (frame and frame.valid) then return end
    local flags = pdata.flags
    local def = at_gui.defines

    frame[def.trash_unrequested].state = flags.trash_unrequested
    frame[def.trash_above_requested].state = flags.trash_above_requested
    frame[def.trash_network].state = flags.trash_network
    frame[def.pause_trash].state = flags.pause_trash
    frame[def.pause_requests].state = flags.pause_requests
    frame[def.status_display].state = flags.status_display_open
end

function at_gui.mark_dirty(pdata, keep_presets)
    local reset = pdata.gui.main.reset_button
    reset.enabled = true
    pdata.flags.dirty = true
    if not keep_presets then
        pdata.selected_presets = {}
    end
    at_gui.update_presets(pdata)
end

function at_gui.destroy(player, pdata)
    if pdata.gui.main and pdata.gui.main.window and pdata.gui.main.window.valid then
        pdata.gui.main.window.destroy()
    end
    pdata.gui.main = {}
    pdata.flags.gui_open = false
    if pdata.gui.import and pdata.gui.import.window then
        if pdata.gui.import.window.main and pdata.gui.import.window.main.valid then
            pdata.gui.import.window.main.destroy()
        end
    end
    pdata.gui.import = {}
    player.set_shortcut_toggled("autotrash-toggle-gui", false)
end

function at_gui.open(player, pdata)
    if not pdata.flags.can_open_gui then return end
    if not player.character then
        player.print{"at-message.no-character"}
        at_gui.close(player, pdata, true)
        return
    end
    local window_frame = pdata.gui.main.window
    if not (window_frame and window_frame.valid) then
        if window_frame then
            player.print{"at-message.invalid-gui"}
        end
        at_gui.destroy(player, pdata)
        at_gui.create_main_window(player, pdata)
        window_frame = pdata.gui.main.window
    end
    window_frame.visible = true
    window_frame.bring_to_front()
    pdata.flags.gui_open = true
    if not pdata.flags.pinned then
        player.opened = window_frame
    end
    player.set_shortcut_toggled("autotrash-toggle-gui", true)

    at_gui.adjust_slots(player, pdata)
    at_gui.update_buttons(pdata)
    at_gui.update_button_styles(player, pdata)
    at_gui.update_settings(pdata)
    at_gui.update_sliders(pdata)
    at_gui.update_presets(pdata)
end

function at_gui.close(player, pdata, no_reset)
    local window_frame = pdata.gui.main.window
    if window_frame and window_frame.valid then
        window_frame.visible = false
    end
    pdata.flags.gui_open = false
    pdata.selected = false
    if not pdata.flags.pinned then
        player.opened = nil
    end
    if pdata.gui.main.networks and pdata.gui.main.presets then
        pdata.gui.main.networks.visible = false
        pdata.gui.main.presets.visible = true
        pdata.gui.main.network_edit_button.style = "tool_button"
    end
    if not no_reset and pdata.settings.reset_on_close then
        pdata.config_tmp = table.deep_copy(pdata.config_new)
        pdata.gui.main.reset_button.enabled = false
        pdata.dirty = false
    end
    player.set_shortcut_toggled("autotrash-toggle-gui", false)
end

function at_gui.recreate(player, pdata)
    local was_open = pdata.flags.gui_open
    at_gui.destroy(player, pdata)
    if was_open then
        at_gui.open(player, pdata)
    else
        player.set_shortcut_toggled("autotrash-toggle-gui", false)
        at_gui.create_main_window(player, pdata)
    end
end

function at_gui.toggle(player, pdata)
    if pdata.flags.gui_open then
        at_gui.close(player, pdata)
    else
        at_gui.open(player, pdata)
    end
end
return at_gui