-- scriptname: ISOSEQ 16
-- v1.0.0: @carvingcode
-- https://llllllll.co/t/isoseq/21026

--
-- vars
--

engine.name = 'Passersby'
local Passersby = require "we/lib/passersby"

local app_title = "ISOSEQ 16"

local UI = require "ui"
local MusicUtil = require 'musicutil'
local beat_clock = require 'beatclock'

-- device vars
local grid_device = grid.connect()
local midi_in_device = midi.connect()
local midi_out_device = midi.connect()
local midi_out_channel

-- param vars
local out_options = {"Audio", "MIDI", "Audio + MIDI"}
local grid_display_options = {"Normal", "180 degrees"}
local DATA_FILE_PATH = _path.data .. "ccode/isoseq16/isoseq16.data"

local alt = false
local app_mode -- 1 = pause, 2 = seq on, 3 = edit

-- clocking variables
local position = 0

-- grid variables
local light = 0
local grid_pad = {}
local grid_pad_lights = 1
local root_lights
local row
local col

-- sequence vars
local max_pages = 16
local num_pages = 1
local active_page = 1
local page_auto_advance = false
local page_advance = 1

-- scale vars
local scale = {}
local notes_played = {}
local root_num = 48
local tonic = MusicUtil.note_num_to_name(48, 1)
local mode
local note
local note_sounding = 0

-- pattern vars
local pattern_len = 16
local position = 1
local show_marker = false

-- clock vars
local beat_clock = beat_clock.new()
local beat_clock_midi = midi.connect()
beat_clock_midi.event = beat_clock.process_midi

-- UI vars
local SCREEN_FRAMERATE = 15
local screen_refresh_metro
local screen_dirty = true
local GRID_FRAMERATE = 30
local grid_dirty = true
local pages
local playback_icon

-- load/save/delete
local save_data = {version = 1, patterns = {}}
local save_menu_items = {"Load", "Save", "Delete"}
local save_slot_list
local save_menu_list
local last_edited_slot = 0
local confirm_message
local confirm_function

--
-- load/save/delete function @markeats
--
local function copy_object(object)
  if type(object) ~= 'table' then return object end
  local result = {}
  for k, v in pairs(object) do result[copy_object(k)] = copy_object(v) end
  return result
end

local function update_save_slot_list()
  local entries = {}
  for i = 1, math.min(#save_data.patterns + 1, 999) do
    local entry
    if i <= #save_data.patterns then
      entry = save_data.patterns[i].name
    else
      entry = "-"
    end
    if i == last_edited_slot then entry = entry .. "*" end
    entries[i] = i .. ". " .. entry
  end
  save_slot_list.entries = entries
end

local function read_data()
  local disk_data = tab.load(DATA_FILE_PATH)
  if disk_data then
    if disk_data.version then
      if disk_data.version == 1 then
        save_data = disk_data
      else
        print("Unrecognized data, version " .. disk_data.version)
      end
    end
  end
  update_save_slot_list()
end

local function write_data()
  tab.save(save_data, DATA_FILE_PATH)
end

local function load_pattern(index)
  if index > #save_data.patterns then return end
  
  local pattern = copy_object(save_data.patterns[index])
    params:set("bpm", pattern.bpm)

    root_num = pattern.root_num
    mode = pattern.mode
    pattern_len = pattern.pattern_len
    num_pages = pattern.num_pages
    page_advance = pattern.page_advance
    page_auto_advance = pattern.page_auto_advance
    grid_pad_lights = pattern.grid_pad_lights
    grid_pad = pattern.grid_pad
    notes_played = pattern.notes_played
    scale = pattern.scale
  
    active_page = 1
    tonic = MusicUtil.note_num_to_name(root_num, 1)

  last_edited_slot = index
  update_save_slot_list()
  grid_dirty = true
end

local function save_pattern(index)
  local pattern = {
    name = os.date("%b %d %H:%M"),
    bpm = params:get("bpm"),

    root_num = root_num,
    mode = mode,
    pattern_len = pattern_len,
    num_pages = num_pages,
    page_advance = page_advance,
    page_auto_advance = page_auto_advance,
    grid_pad_lights = grid_pad_lights,
    grid_pad = grid_pad,
    notes_played = notes_played,
    scale = scale
  }
  
  save_data.patterns[index] = copy_object(pattern)
  last_edited_slot = index
  update_save_slot_list()
  
  write_data()
end

local function delete_pattern(index)
  if index > 0 and index <= #save_data.patterns then
    table.remove(save_data.patterns, index)
    if index == last_edited_slot then
      last_edited_slot = 0
    elseif index < last_edited_slot then
      last_edited_slot = last_edited_slot - 1
    end
  end
  update_save_slot_list()
  
  write_data()
end
-------------

--
-- util functions
--
local function all_notes_kill()
  
  -- Audio engine out
  if (params:get("output") == 1 or params:get("output") == 3) then
    engine.amp(0)
  end
  
  -- MIDI out
  midi_out_device:note_off(note_sounding, nil)
  note_sounding = 0
end

function reset_pattern()

end

local function turn_note_off(current_note)


  -- Audio engine out
  if (params:get("output") == 1 or params:get("output") == 3) then
    engine.noteOff(current_note)
  end

  -- MIDI out
  if (params:get("output") == 2 or params:get("output") == 3) then
    midi_out_device:note_off(current_note, nil)
  end

  current_note = 0
end

local function init_scale()
  -- build 8 rows of scales, each a perfect 4th apart
  local root = root_num
  for row = 8, 1, -1 do
      scale[row] = MusicUtil.generate_scale_of_length(root,MusicUtil.SCALES[mode].name, 16)
      -- create rows are 4th apart, lower octave at bottom row (row 8), higher at top (row 1)
      root = root + 5 
  end
end

local function init_root_lights()
  -- build table of root locations on grid
  root_lights = {}
  for r = 1, #MusicUtil.SCALES[mode].intervals do
    if r == 1 then
      root_lights[r] = root_num
    else
      local root = root_lights[r-1] + #MusicUtil.SCALES[mode].intervals-1
      root_lights[r] = root
    end
  end
end

local function random_notes()

  for p = 1, max_pages do
    for col = 1, 16 do
      for row = 1, 8 do
        notes_played[p][col][row].note = 0
       end
    end
  end

  -- enter random pattern
  for p = 1, max_pages do
    for col = 1, 16 do
      notes_played[p][col][math.random(1,8)].note = math.random(0,1)
    end
  end
end


--
-- sequence stuff
--
function handle_step()

  position = (position % pattern_len) + 1

  for row = 1, 8 do
    if notes_played[active_page][position][row].note == 1 then
      if note_sounding ~= scale[row][position] then
        turn_note_off(note_sounding)
      end

      local vel = math.random(1,100) / 100 -- random velocity values
      -- Audio engine out
      if params:get("output") == 1 or params:get("output") == 3 then
        engine.amp(vel)
        engine.noteOn(1, MusicUtil.note_num_to_freq(scale[row][position]), 1)
      end

      if (params:get("output") == 2 or params:get("output") == 3) then
        note_sounding = MusicUtil.freq_to_note_num(MusicUtil.note_num_to_freq(scale[row][position]),1)
        midi_out_device:note_on(note_sounding,vel*100)

        note_sounding = scale[row][position]
      end
    end
  end

  if position == pattern_len and page_auto_advance then 
    if active_page < num_pages then
      active_page = active_page + 1
    else
      active_page = 1
    end
  end

  grid_dirty = true

end


--
-- grid stuff
--

function grid_device.key(x, y, z)

  -- pad pressed, so toggle light
  if z == 1 then
    
    -- set/unset led for pad pressed
    notes_played[active_page][x][y].note = notes_played[active_page][x][y].note == 1 and 0 or 1
    -- turn off any other led in row
    for row = 1, 8 do
      if row ~= y then
        if notes_played[active_page][x][row].note == 1 then
          notes_played[active_page][x][row].note = 0
        end 
      end
    end
    -- send note off for previous note
    if note_sounding ~= scale[y][x] then
      turn_note_off(note_sounding)
    end      
    if app_mode ~= 2 then
    local vel = math.random(1,100) / 100 -- random velocity values
    engine.amp(vel)
    engine.noteOn(1, MusicUtil.note_num_to_freq(scale[y][x]), 1)
end
 end
 -- store this note
 note_sounding = scale[y][x]
  
 grid_dirty = true

end

function grid_redraw()

  grid_device:all(0)

  -- draw isomorphic layout and step marker
  for col = 1, 16 do
    for row = 1, 8 do
      if grid_pad[col][row].light == 1 then

        if tab.contains(root_lights, scale[row][col]) then
          grid_device:led(col, row, (grid_pad_lights == 1 and 4 or 0))
        else
          grid_device:led(col, row, (grid_pad_lights == 1 and 2 or 0))
        end
      else
        grid_device:led(col, row, 0)
      end
      -- step marker
      if app_mode == 2 and show_marker then
        grid_device:led(position,row,6)
      end
    end
  end

  -- draw sequence pattern in lights
    for col = 1, 16 do
      for row = 1, 8 do
        if notes_played[active_page][col][row].note == 1 then
          -- adjust led brightness to pattern size
          if col > pattern_len then
            grid_device:led(col, row, 5)
          else
            grid_device:led(col, row, 15)
          end
        end
      end
    end

  screen_dirty = true

  grid_device:refresh()

end


--
-- norns stuff
--

function key(n,z)

  if n==1 then
    alt = z==1
  end

  if z == 1 then

    if alt and n == 2 then 

      random_notes()
      grid_dirty = true

    elseif n == 2 then

      if pages.index == 1 or pages.index == 2 then
        -- show sequence page to be edited
        show_marker = false

        app_mode = 3 -- edit

        all_notes_kill()
      
        beat_clock:stop()

        grid_dirty = true
        screen_dirty = true

      elseif pages.index == 3 then
      
        if confirm_message then
          confirm_message = nil
          confirm_function = nil
        end
      end
  
    elseif n == 3 then

      if pages.index == 1 or pages.index == 2 then
        if app_mode == 2 then
          -- stop sequence, turn of lights, go home
          show_marker = false

          app_mode = 1 -- pause

          all_notes_kill()
          beat_clock:stop()

          grid_device:all(0)
          grid_device:refresh()

        else
          -- start sequence
          grid_lights_on = true
          show_marker = true

          position = 0

          app_mode = 2 -- seq on

          grid_dirty = true
          beat_clock:start()

        end

      -- Load/Save
      elseif pages.index == 3 then
          
        if confirm_message then
          confirm_function()
          confirm_message = nil
          confirm_function = nil

        else
          -- Load
          if save_menu_list.index == 1 then
            load_pattern(save_slot_list.index)
          
          -- Save
          elseif save_menu_list.index == 2 then
            if save_slot_list.index < #save_slot_list.entries then
              confirm_message = UI.Message.new({"Replace saved pattern?"})
              confirm_function = function() save_pattern(save_slot_list.index) end
            else
              save_pattern(save_slot_list.index)
            end
            
          -- Delete
          elseif save_menu_list.index == 3 then
            if save_slot_list.index < #save_slot_list.entries then
              confirm_message = UI.Message.new({"Delete saved pattern?"})
              confirm_function = function() delete_pattern(save_slot_list.index) end
            end
          end     
        end
      end
    end
	screen_dirty = true

  end
end


--
-- norns encoders
--
function enc(n, delta)

  -- handle UI paging
  if n == 1 then
  -- Page scroll
      pages:set_index_delta(util.clamp(delta, -1, 1), false)
  end
  
  if pages.index == 1 then

    if n == 2 then	
      -- tonic
      local root = root_num
      root = util.clamp(root + delta, 24, 72)
      tonic = MusicUtil.note_num_to_name(root, 1)
      for row = 8, 1, -1 do
        scale[row] = MusicUtil.generate_scale_of_length(root, MusicUtil.SCALES[mode].name, 16)
        -- create rows are 4th apart, lower octave at bottom row (row 8), higher at top (row 1)
        root = root + 5 
        -- reset root num
        if row == 8 then
        root_num = scale[row][1]
        end
      end
      
      init_root_lights()

    elseif n == 3 then       
      params:delta("bpm",delta)
    end


  elseif pages.index == 2 then

    if alt and n == 2 then       
      -- pattern length
      pattern_len = util.clamp(pattern_len + delta, 2, 16)
      
    elseif n == 2 then
      -- number of pages
      num_pages = util.clamp(num_pages + delta, 1, max_pages)

    elseif alt and n == 3 then       
      -- page advance
      page_advance = util.clamp(page_advance + delta, 1, 2)

    elseif n == 3 then
      -- set active page
      active_page = util.clamp(active_page + delta, 1, num_pages)

    end
    -- Load/Save
  elseif pages.index == 3 then
      
    if n == 2 then
      save_slot_list:set_index_delta(util.clamp(delta, -1, 1))
        
    elseif n == 3 then
      save_menu_list:set_index_delta(util.clamp(delta, -1, 1))
        
    end

  end

  grid_dirty = true
  screen_dirty = true
end


--
-- norns screen redraw
--
function redraw()

  screen.clear()

  screen.aa(1)

  if confirm_message then
    confirm_message:redraw()
    
  else

    pages:redraw()

    if beat_clock.playing then
      playback_icon.status = 1
    else
      if app_mode > 2 then 
        playback_icon.status = 4
      else
        playback_icon.status = 3
      end
    end
    if pages.index ~= 3 then
      playback_icon:redraw()
    end

    screen.line_width(1)
    screen.move(63,10)
    screen.level(10)
    screen.font_size(12)
    screen.font_face(14)
    screen.text_center(app_title)

    if pages.index == 1 then
	    
      screen.font_size(8)
      screen.font_face(1)

      screen.move(5,30)
      screen.level(5)
      screen.text("Key: ")
      screen.move(30,30)
      screen.level(15)
      screen.text(tonic)

      screen.move(65,30)
      screen.level(5)
      screen.text("BPM: ")
      screen.move(90,30)
      if beat_clock.external then
        screen.level(3)
        screen.text("Ext")
      else
        screen.level(15)
        screen.text(params:get("bpm"))
      end

    elseif pages.index == 2 then  

      screen.font_size(8)
      screen.font_face(1)

      screen.move(5,30)
      screen.level(5)
      screen.text("# Pages: ")
      screen.move(45,30)
      screen.level(15)
      screen.text(num_pages)
      screen.move(65,30)
      screen.level(5)
      screen.text("Current: ")
      screen.move(105,30)
      screen.level(15)
      screen.text(active_page)

      screen.move(5,40)
      screen.level(5)
      screen.text("# Steps: ")
      screen.move(45,40)
      screen.level(15)
      screen.text(pattern_len)
      screen.move(65,40)
      screen.level(5)
      screen.text("Advance: ")
      screen.move(105,40)
      screen.level(15)
      if page_advance == 1 then
        page_auto_advance = false
        screen.text("Off")
      else
        page_auto_advance = true
        screen.text("A")
        if show_marker then screen.text(":"..active_page) end 
      end
                
    elseif pages.index == 3 then

      screen.font_size(8)
      screen.font_face(1)

      save_slot_list:redraw()
      save_menu_list:redraw()

    end
  end
  screen.update()
end


--
-- startup
--

function init()

  -- set up table of pages, pads and notes
  for p = 1, max_pages do
    notes_played[p] = {}
    for col = 1, 16 do
      grid_pad[col] = {}
      notes_played[p][col] = {}
      for row = 1, 8 do
        grid_pad[col][row] = {}  
        notes_played[p][col][row] = {}
        grid_pad[col][row].light = 1
        notes_played[p][col][row].note = 0
      end
    end
  end

  -- Chromatic for isomorphic layout
  for k, v in pairs(MusicUtil.SCALES) do
    if v.name == "Chromatic" then
      mode = k
      break
    end
  end

  init_scale()

  init_root_lights()


  local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
    --screen_update()
    if screen_dirty then
      screen_dirty = false
      redraw()
    end
  end
  
  local grid_redraw_metro = metro.init()
  grid_redraw_metro.event = function()
    --grid_update()
    if grid_dirty and grid_device.device then
      grid_dirty = false
      grid_redraw()
    end
  end

-- set clock functions
    beat_clock.on_step = handle_step
    beat_clock.on_stop = all_notes_kill
    beat_clock.on_select_external = all_notes_kill

	-- set up parameter menu

    params:add_number("bpm", "BPM", 1, 480, beat_clock.bpm)
    params:set_action("bpm", function(x) beat_clock:bpm_change(x) end)
    params:set("bpm", 72)
     

    params:add_separator()
    
    params:add{type = "number", id = "grid_device", name = "Grid Device", min = 1, max = 4, default = 1, 
        action = function(value)
        grid_device:all(0)
        grid_device:refresh()
        grid_device = grid.connect(value)
    end}

	params:add_option("grid_rotation", "Grid Rotation", grid_display_options)
	params:set_action("grid_rotation", function(x) 
      local val
      if x == 1 then val = 0 else val = 2 end
		grid_device:rotation(val)
    grid_dirty = true
	end) 

  params:add_option("grid_pad_lights", "Layout Lights", {"On", "Off"}, 1 or 2)
	params:set_action("grid_pad_lights", function(x) grid_pad_lights = x grid_dirty = true end)

    params:add_separator()
    
    params:add{type = "option", id = "output", name = "Output", options = out_options, 
        action = function()all_notes_kill()end}
        
    params:add{type = "number", id = "midi_out_device", name = "MIDI Out Device", min = 1, max = 4, default = 1,
        action = function(value)
        midi_out_device = midi.connect(value)
    end}
  
    params:add{type = "number", id = "midi_out_channel", name = "MIDI Out Channel", min = 1, max = 16, default = 1,
        action = function(value)
        all_notes_kill()
        midi_out_channel = value
    end}
    
	params:add{type = "number", id = "clock_midi_in_device", name = "Clock MIDI In Device", min = 1, max = 4, default = 1,
    	action = function(value)
		midi_in_device = midi.connect(value)
    end}
    
  	params:add_option("clock", "Clock Source", {"Internal", "External"}, beat_clock.external or 2 and 1)
	params:set_action("clock", function(x) beat_clock:clock_source_change(x) end)
	
	params:add{type = "option", id = "clock_out", name = "Clock Out", options = {"Off", "On"}, default = beat_clock.send or 2 and 1,
    	action = function(value)
		if value == 1 then beat_clock.send = false
		else beat_clock.send = true end
    end}
  
    params:add_separator()

    Passersby.add_params()
	-- set up MIDI in
    midi_in_device.event = function(data)
    	beat_clock:process_midi(data)
		if not beat_clock.playing then
			screen_dirty = true
    	end
	end
    
-- rotate test grid
	--grid_device:rotation(2)

  -- UI
  
  pages = UI.Pages.new(1, 3)
  save_slot_list = UI.ScrollingList.new(5, 20, 1, {})
  save_slot_list.num_visible = 3
  save_slot_list.num_above_selected = 0
  save_menu_list = UI.List.new(92, 20, 1, save_menu_items)
  playback_icon = UI.PlaybackIcon.new(121, 55)
  
  app_mode = 1

  screen.aa(1)
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  grid_redraw_metro:start(1 / GRID_FRAMERATE)

  -- Data
  read_data()
end


function cleanup ()
  beat_clock:stop()
end
