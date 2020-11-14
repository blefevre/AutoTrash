local table = require("__flib__.table")
local floor = math.floor
local constants = require("constants")

local M = {}

local item_prototypes = {}
M.item_prototype = function(name)
    if item_prototypes[name] then
        return item_prototypes[name]
    end
    item_prototypes[name] = game.item_prototypes[name]
    return item_prototypes[name]
end

M.swap_configs = function(pdata, origin, destination)
    local config_tmp = pdata.config_tmp
    local old_config = config_tmp.config[origin]
    local tmp = table.deep_copy(config_tmp.config[destination])
    config_tmp.config[destination] = table.deep_copy(old_config)
    config_tmp.config[destination].slot = destination
    config_tmp.by_name[old_config.name] = config_tmp.config[destination]
    if tmp then
        config_tmp.config[origin] = tmp
        config_tmp.by_name[tmp.name] = tmp
        tmp.slot = origin
    else
        config_tmp.config[origin] = nil
    end
    config_tmp.max_slot = destination > config_tmp.max_slot and destination or config_tmp.max_slot
end

M.add_config = function(pdata, name, min, max, index)
    local config_tmp = pdata.config_tmp
    config_tmp.config[index] = {
        name = name, min = min,
        max = max, slot = index
    }
    config_tmp.by_name[name] = config_tmp.config[index]

    config_tmp.max_slot = index > config_tmp.max_slot and index or config_tmp.max_slot
    if config_tmp.config[index].min > 0 then
        config_tmp.c_requests = config_tmp.c_requests + 1
    end
end

M.clear_config = function(pdata, index)
    local config_tmp = pdata.config_tmp
    local config = config_tmp.config[index]
    if config then
        if config.min > 0 then
            config_tmp.c_requests = config_tmp.c_requests > 0 and config_tmp.c_requests - 1 or 0
        end
        if pdata.selected == index then pdata.selected = false end
        config_tmp.by_name[config.name] = nil
        config_tmp.config[index] = nil
        if index == config_tmp.max_slot then
            config_tmp.max_slot = 0
            for i = index-1, 1, -1 do
                if config_tmp.config[i] then
                    config_tmp.max_slot = i
                    break
                end
            end
        end
    end
end

M.check_config = function(player, pdata)
    local adjusted
    for _, config in pairs(pdata.config_tmp.config) do
        if config.max < config.min then
            adjusted = true
            config.max = config.min
            player.print{"at-message.adjusted-trash-amount", M.item_prototype(config.name).localised_name, config.max}
        end
    end
    return adjusted
end

-- function M.get_quickbar_items(player, pdata)
--     local items = {}
--     local quickbars = 4
--     local get_active_page = player.get_active_quick_bar_page
--     local get_slot = player.get_quick_bar_slot
--     for screen_index = 1, quickbars do
--         local offset = (get_active_page(screen_index) - 1) * 10
--         local start = offset + 1
--         for i = start, start + 9 do
--             local item = get_slot(i)
--             if item then
--                 local slot = (i - offset)+((screen_index-1)*10)
--                 assert(not items[slot])
--                 items[slot] = item.name
--             end
--         end
--     end
--     return items
-- end

-- M.set_requests2 = function(player, pdata)
--     local character = player.character
--     if not character then return end
--     local flags = pdata.flags
--     local config_new = pdata.config_new
--     local storage = config_new.config
--     local slot_count = player.character_logistic_slot_count
--     local set_request_slot = character.set_personal_logistic_slot
--     local clear_request_slot = character.clear_personal_logistic_slot
--     local trash_paused = flags.pause_trash
--     local trash_above_requested = flags.trash_above_requested
--     local requests_paused = flags.pause_requests
--     local contents = flags.trash_unrequested and player.get_main_inventory().get_contents()
--     local temporary_requests = pdata.temporary_requests
--     local handled_temporary = {}

--     local quickbars = 4
--     local needed_slots = quickbars*10 + config_new.max_slot
--     if needed_slots > slot_count then
--         player.character_logistic_slot_count = needed_slots
--         slot_count = needed_slots
--     end
--     local max_request = constants.max_request
--     local quickbar_items = M.get_quickbar_items(player, pdata)
--     local already_requested = {}
--     for i = 1, quickbars * 10 do
--         clear_request_slot(i)
--         local name = quickbar_items[i]
--         if name and not constants.trash_blacklist[M.item_prototype(name).type] then
--             local min = config_new.by_name[name] and config_new.by_name[name].min or M.item_prototype(name).stack_size
--             local max = config_new.by_name[name] and config_new.by_name[name].max or max_request
--             set_request_slot(i, {name = name, min = min, max = max})
--             already_requested[name] = true
--         end
--     end
--     local offset = quickbars * 10
--     for c = offset + 1, slot_count do
--         local min
--         local max = max_request
--         --TODO: move in else block for 1.1
--         clear_request_slot(c)
--         local req = storage[c - offset]
--         if req and not already_requested[req.name] then
--             local name = req.name
--             if temporary_requests[name] then
--                 req = temporary_requests[name].temporary
--                 handled_temporary[name] = true
--             end
--             local request = req.min
--             min = requests_paused and 0 or request
--             if not trash_paused then
--                 max = (trash_above_requested and request > 0) and request or req.max
--                 if contents and contents[name] then
--                     contents[name] = nil
--                 end
--             end
--             set_request_slot(c, {name = name, min = min, max = max})
--         end
--     end

--     --handle remaining temporary requests
--     for name, request_data in pairs(temporary_requests) do
--         if not handled_temporary[name] then
--             local temp_request = request_data.temporary
--             set_request_slot(temp_request.index, temp_request)
--             if contents and contents[name] then
--                 contents[name] = nil
--             end
--         end
--     end

--     --trash unrequested items
--     if contents and not trash_paused then
--         if not next(contents) then return end

--         for name, _ in pairs(contents) do
--             if constants.trash_blacklist[M.item_prototype(name).type] then
--                 contents[name] = nil
--             end
--         end
--         local c_contents = table_size(contents)
--         if slot_count < config_new.max_slot + c_contents then
--             player.character_logistic_slot_count = slot_count + c_contents
--         end

--         local i = config_new.max_slot + 1
--         for name, _ in pairs(contents) do
--             set_request_slot(i, {name = name, max = 0})
--             i = i + 1
--         end
--     end
-- end

M.set_requests = function(player, pdata)
    local character = player.character
    if not character then return end
    local flags = pdata.flags
    local config_new = pdata.config_new
    local storage = config_new.config
    local slot_count = player.character_logistic_slot_count
    local set_request_slot = character.set_personal_logistic_slot
    local clear_request_slot = character.clear_personal_logistic_slot
    local trash_paused = flags.pause_trash
    local trash_above_requested = flags.trash_above_requested
    local requests_paused = flags.pause_requests
    local contents = flags.trash_unrequested and player.get_main_inventory().get_contents()
    local temporary_requests = pdata.temporary_requests
    local handled_temporary = {}

    if config_new.max_slot > slot_count then
        player.character_logistic_slot_count = config_new.max_slot
        slot_count = config_new.max_slot
    end

    local max_request = constants.max_request
    for c = 1, slot_count do
        local min
        local max = max_request
        --TODO: move in else block for 1.1
        clear_request_slot(c)
        local req = storage[c]
        if req then
            local name = req.name
            if temporary_requests[name] then
                req = temporary_requests[name].temporary
                handled_temporary[name] = true
            end
            local request = req.min
            min = requests_paused and 0 or request
            if not trash_paused then
                max = (trash_above_requested and request > 0) and request or req.max
                if contents and contents[name] then
                    contents[name] = nil
                end
            end
            set_request_slot(c, {name = name, min = min, max = max})
        end
    end

    --handle remaining temporary requests
    for name, request_data in pairs(temporary_requests) do
        if not handled_temporary[name] then
            local temp_request = request_data.temporary
            set_request_slot(temp_request.index, temp_request)
            if contents and contents[name] then
                contents[name] = nil
            end
        end
    end

    --trash unrequested items
    if contents and not trash_paused then
        if not next(contents) then return end

        for name, _ in pairs(contents) do
            if constants.trash_blacklist[M.item_prototype(name).type] then
                contents[name] = nil
            end
        end
        local c_contents = table_size(contents)
        if slot_count < config_new.max_slot + c_contents then
            player.character_logistic_slot_count = slot_count + c_contents
        end

        local i = config_new.max_slot + 1
        for name, _ in pairs(contents) do
            set_request_slot(i, {name = name, max = 0})
            i = i + 1
        end
    end
end

M.pause_requests = function(player, pdata)
    pdata.flags.pause_requests = true
    M.set_requests(player, pdata)
end

M.unpause_requests = function(player, pdata)
    pdata.flags.pause_requests = false
    M.set_requests(player, pdata)
end

M.pause_trash = function(player, pdata)
    pdata.flags.pause_trash = true
    M.set_requests(player, pdata)
end

M.unpause_trash = function(player, pdata)
    pdata.flags.pause_trash = false
    M.set_requests(player, pdata)
end

M.get_non_equipment_network = function(character)
    if not character then return end
    --trash slots researched
    local logi_point = character.get_logistic_point(defines.logistic_member_index.character_provider)
    if not logi_point then
        --requests researched
        logi_point = character.get_logistic_point(defines.logistic_member_index.character_requester)
    end
    return logi_point and logi_point.logistic_network
end

M.get_network_entity = function(player)
    local network = M.get_non_equipment_network(player.character)
    if network and network.valid then
        local cell = network.find_cell_closest_to(player.position)
        return cell and cell.owner
    end
    return false
end

M.in_network = function(player, pdata)
    if not pdata.flags.trash_network then
        return true
    end
    local currentNetwork = M.get_non_equipment_network(player.character)
    if not (currentNetwork and currentNetwork.valid) then
        return false
    end
    for id, network in pairs(pdata.networks) do
        if network and network.valid then
            if currentNetwork == network.logistic_network then
                return true
            end
        elseif network and not network.valid then
            player.print({"at-message.network-lost", id})
            pdata.networks[id] = nil
        end
    end
    return false
end

M.format_number = function(n, append_suffix)
    local amount = tonumber(n)
    if not amount then
    return n
    end
    local suffix = ""
    if append_suffix then
        local suffix_list = {
            ["T"] = 1000000000000,
            ["B"] = 1000000000,
            ["M"] = 1000000,
            ["k"] = 1000
        }
        for letter, limit in pairs (suffix_list) do
            if math.abs(amount) >= limit then
                amount = floor(amount/(limit/10))/10
                suffix = letter
                break
            end
        end
    end
    local formatted, k = amount
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then
            break
        end
    end
    return formatted..suffix
end

M.remove_invalid_items = function()
    local function _remove(tbl)
        for i = tbl.max_slot, 1, -1 do
            local item_config = tbl.config[i]
            if item_config then
                if not M.item_prototype(item_config.name) then
                    if tbl.config[i].min > 0 then
                        tbl.c_requests = tbl.c_requests - 1
                    end
                    tbl.by_name[item_config.name] = nil
                    tbl.config[i] = nil
                    if tbl.max_slot == i then
                        tbl.max_slot = false
                    end
                else
                    tbl.max_slot = tbl.max_slot or i
                end
            end
        end
    end
    for _, pdata in pairs(global._pdata) do
        if pdata.config_new and pdata.config_tmp then
            _remove(pdata.config_new)
            _remove(pdata.config_tmp)
        end
        if pdata.presets then
            for _, stored in pairs(pdata.presets) do
                _remove(stored)
            end
        end
    end
end

return M