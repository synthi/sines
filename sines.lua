--- sines v1.0.0 ~
-- @oootini, @p3r7, @sixolet, @tomwaters
-- z_tuning lib by @catfact
--
-- ,-.   ,-.   ,-.
--    `-'   `-'   `-'
--
-- ▼ controls ▼
--
-- E1 - select crow chord
-- E2 - active sine
--
-- active sine control:
-- E3 - sine volume
-- K2 + E2 - note *
-- K2 + E3 - detune *
-- K2 + K3 - voice panning
-- K3 + E2 - envelope
-- K3 + E3 - FM index
-- K1 + E2 - sample rate
-- K1 + E3 - bit depth
--
-- 16n control:
-- n - sine volume
--
-- 16n advanced controls:
-- n + K2 - detune *
-- n + K3 - FM index
-- n + K1 + K2 - sample rate
-- n + K1 + K3 - bit depth
-- n + K1 + K2 + K3 - note *
--
-- * not used when z_tuning is active
--
-- Change z_tuning in parameters > edit > Z_TUNING 

local sliders = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
local edit = 1
local accum = 1
local params_select = 1
-- env_name, env_bias, attack, decay. bias of 1.0 is used to create a static drone
local envs = {
  {"drone", 1.0, 1.0, 1.0},
  {"am1", 0.0, 0.001, 0.01},
  {"am2", 0.0, 0.001, 0.02},
  {"am3", 0.3, 0.001, 0.05},
  {"pulse1", 0.0, 0.001, 0.2},
  {"pulse2", 0.0, 0.001, 0.5},
  {"pulse3", 0.0, 0.001, 0.8},
  {"pulse4", 0.3, 0.001, 1.0},
  {"ramp1", 0.0, 1.5, 0.01},
  {"ramp2", 0.0, 2.0, 0.01},
  {"ramp3", 0.0, 3.0, 0.01},
  {"ramp4", 0.3, 4.0, 0.01},
  {"evolve1", 0.3, 10.0, 10.0},
  {"evolve2", 0.3, 15.0, 11.0},
  {"evolve3", 0.3, 20.0, 12.0},
  {"evolve4", 0.4, 25.0, 15.0}
}

local env_values = {}
local env_edit = 1
local env_accum = 1
local value = 0
local text = " "
local step = 0
local cents = {}
local notes = {}
local scale_names = {}
local key_1_pressed = 0
local key_2_pressed = 0
local key_3_pressed = 0
local scale_toggle = false
local control_toggle = false
--active state for sliders, params 0-3
local current_state = {15, 2, 2, 2, 2}
local prev_16n_slider_v = {
  vol = {},
  cents = {},
  fm_index = {},
  smpl_rate = {},
  bit_depth = {},
  note = {}
}
local fps = 14
local redraw_clock
local screen_dirty = false

-- TODO crow_outs maps individual sine envelopes to crow outs 1-4.
local crow_outs = {
  {1, 3, 5, 7},
  {1, 5, 8, 10},
  {1, 5, 8, 12},
  {1, 5, 8, 11},
  {1, 5, 9, 11},
  {1, 6, 8, 11},
  {1, 4, 8, 12},
  {1, 4, 8, 10},
  {1, 4, 8, 11},
  {1, 4, 7, 10},
  {1, 4, 7, 11},
  {1, 5, 9, 12}
}

local sample_bitrates = {
  {"hifi", 48000, 24},
  {"clean1", 44100, 12},
  {"clean2", 32000, 10},
  {"clean3", 28900, 10},
  {"grunge1", 34800, 6},
  {"grunge2", 30700, 6},
  {"grunge3", 28600, 6},
  {"lofi1", 24050, 5},
  {"lofi2", 20950, 4},
  {"lofi3", 15850, 3},
  {"crush1", 10000, 3},
  {"crush2", 6000, 2},
  {"crush3", 800, 1}
}

engine.name = "Sines"
_mods = require 'core/mods'
_16n = include "sines/lib/16n"
MusicUtil = require "musicutil"

function init()
  print("loaded sines engine ~")
  add_params()
  edit = 0
  for i = 1, 16 do
    env_values[i] = params:get("env" .. i)
    if not z_tuning then
      cents[i] = params:get("cents" .. i)
    end
    sliders[i] = (params:get("vol" .. i)) * 32
  end

  _16n.init(_16n_slider_callback)
  for i = 1, 16 do
    prev_16n_slider_v["vol"][i] = util.linlin(0.0, 1.0, 0, 127, params:get("vol"..i))
    if not z_tuning then
      prev_16n_slider_v["cents"][i] = util.linlin(-200, 200, 0, 127, params:get("cents"..i))
    end
    prev_16n_slider_v["fm_index"][i] = util.linlin(0.0, 200.0, 0, 127, params:get("fm_index"..i))
    prev_16n_slider_v["smpl_rate"][i] = util.linlin(48000, 480, 0, 127, params:get("smpl_rate"..i))
    prev_16n_slider_v["bit_depth"][i] = util.linlin(24, 1, 0, 127, params:get("bit_depth"..i))
    prev_16n_slider_v["note"][i] = params:get("note"..i)
  end

  redraw_clock = clock.run(
    function()
      local step_s = 1 / fps
      while true do
        clock.sleep(step_s)
        if screen_dirty then
          set_active()
          redraw()
          screen_dirty = false
        end
      end
    end)

  --check if z_tuning
  local ztuning
  if _mods.is_enabled('z_tuning') then
    z_tuning = require('z_tuning/lib/mod')
  end

  -- if z_tuning, configure and refresh all sine freqs when z_tuning changes
  if z_tuning then
    z_tuning.set_tuning_change_callback(
      function()
        local num, hz
        for voice = 1, 16 do
          num = params:get("note" .. voice)
          hz = MusicUtil.note_num_to_freq(num)
          engine.hz(voice - 1, hz)
          if norns.crow.connected() then
            set_crow_note(voice, hz)
          end
        end
      end)
  end

end

function cleanup()
  clock.cancel(redraw_clock)
end

function is_prev_16n_slider_v_crossing(mode, i, v)
  local prev_v = prev_16n_slider_v[mode][i]
  if mode ~= "vol" then
    return true
  end
  if prev_v == nil then
    return true
  end
  if math.abs(v - prev_v) < 10 then
    return true
  end
  return false
end

function _16n_slider_callback(midi_msg)
  local slider_id = _16n.cc_2_slider_id(midi_msg.cc)
  local v = midi_msg.val

  if params:string("16n_auto") == "no" then
    return
  end
  -- update current slider
  params:set("fader" .. slider_id, v)
end

function virtual_slider_callback(slider_id, v)
  accum = slider_id - 1
  edit = accum

  if is_prev_16n_slider_v_crossing("vol", slider_id, v) then
    params:set("vol" .. edit + 1, util.linlin(0, 127, 0.0, 1.0, v))
    prev_16n_slider_v["vol"][slider_id] = v
  end

  screen_dirty = true
end

function add_params()
  --set the scale note values
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5, action = function() set_notes() end}
  params:add{type = "number", id = "root_note", name = "root note",
  min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end, action = function() set_notes() end}

  -- crow outs
  params:add{type = "number", id = "crow_outputs", name = "crow outputs", min = 1, max = 12, default = 5, formatter = function(param) return crow_out_formatter(param:get()) end}

  --16n control
  params:add{type = "option", id = "16n_auto", name = "auto bind 16n", options = {"yes", "no"}, default = 1}

  --amp slew
  params:add_control("amp_slew", "amp slew", controlspec.new(0.01, 10, 'lin', 0.01, 0.01, 's'))
  params:set_action("amp_slew", function(x) set_amp_slew(x) end)

  --global pan settings
  params:add{type = "number", id = "global_pan", name = "global panning", min = 0, max = 1, default = 0, formatter = function(param) return global_pan_formatter(param:get()) end, action = function(x) set_global_pan(x) end}

  --set voice params
  for i = 1, 16 do
    params:add_group("voice " .. i .. " params", 13)
    --set voice vols
    params:add_control("vol" .. i, "vol " .. i, controlspec.new(0.0, 1.0, 'lin', 0.01, 0.0))
    params:set_action("vol" .. i, function(x) set_vol(i - 1, x) end)
    params:add{type = "number", id = "pan" ..i, name = "pan " .. i, min = -1, max = 1, default = 0, formatter = function(param) return pan_formatter(param:get()) end, action = function(x) set_synth_pan(i - 1, x) end}
    params:add{type = "number", id = "note" ..i, name = "note " .. i, min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end, action = function(x) set_note(i - 1, x) end}
    if not z_tuning then
      params:add_control("cents" .. i, "cents detune " .. i, controlspec.new(-200, 200, 'lin', 1, 0, 'cents'))
      params:set_action("cents" .. i, function(x) tune(i - 1, x) end)
    end
    params:add_control("fm_index" .. i, "fm index " .. i, controlspec.new(0.0, 200.0, 'lin', 1.0, 3.0))
    params:set_action("fm_index" .. i, function(x) set_fm_index(i - 1, x) end)
    params:add{type = "number", id = "env" ..i, name = "env " .. i, min = 1, max = 16, default = 1, formatter = function(param) return env_formatter(param:get()) end, action = function(x) set_env(i, x) end}
    params:add_control("attack" .. i, "env attack " .. i, controlspec.new(0.01, 15.0, 'lin', 0.01, 1.0, 's'))
    params:set_action("attack" .. i, function(x) set_amp_atk(i - 1, x) end)
    params:add_control("decay" .. i, "env decay " .. i, controlspec.new(0.01, 15.0, 'lin', 0.01, 1.0, 's'))
    params:set_action("decay" .. i, function(x) set_amp_rel(i - 1, x) end)
    params:add_control("env_bias" .. i, "env bias " .. i, controlspec.new(0.0, 1.0, 'lin', 0.1, 1.0))
    params:set_action("env_bias" .. i, function(x) set_env_bias(i - 1, x) end)

    params:add{type = "number", id = "eoc_delay" .. i, name = "env delay " .. i, min = 0, max = 2000, default = 0, formatter = function(param) return eoc_delay_formatter(param:get()) end, action = function(x) set_amp_eoc_delay(i - 1, x) end}

    params:add{type = "number", id = "sample_bitrate" .. i, name = "sample bitrate " .. i, min = 1, max = 13, default = 1, formatter = function(param) return sample_bitrate_formatter(param:get()) end, action = function(x) set_sample_bitrate(i, x) end}
    params:add_control("bit_depth" .. i, "bit depth " .. i, controlspec.new(1, 24, 'lin', 1, 24, 'bits'))
    params:set_action("bit_depth" .. i, function(x) set_bit_depth(i - 1, x) end)
    params:add_control("smpl_rate" .. i, "sample rate " .. i, controlspec.new(480, 48000, 'lin', 100, 48000, 'hz'))
    params:set_action("smpl_rate" .. i, function(x) set_sample_rate(i - 1, x) end)
  end
  --set virtual faders params
  params:add_group("virtual faders", 16)
  for i = 1, 16 do
    params:add{type = "number", id = "fader" ..i, name = "fader " .. i, min = 0, max = 127, default = 0, action = function(v) virtual_slider_callback(i, v) end}
  end
  params:read()
  params:bang()
end

function build_scale()
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 16)
  local num_to_add = 16 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[16 - num_to_add])
  end
end

function set_notes()
  build_scale()
  scale_toggle = true
  for i = 1, 16 do
    params:set("note" .. i, notes[i])
    local hz_value = MusicUtil.note_num_to_freq(notes[i])
    if norns.crow.connected() then
      set_crow_note(i, hz_value)
    end
  end
end

function hz_to_1voct(hz, root_freq)
  local v_oct = math.log10(hz/root_freq)/math.log10(2)
  return v_oct
end

function set_crow_note(synth_voice, hz)
  for i = 1, 4 do
    local crow_voice = crow_outs[params:get("crow_outputs")][i]
    if crow_voice == synth_voice then
      if z_tuning then
        crow.output[i].volts = hz_to_1voct(hz, params:get("zt_root_freq"))
      else
        crow.output[i].volts = params:get("note" .. crow_voice)/12
      end
    end
  end
end

function set_amp_slew(slew_rate)
  -- set the slew rate for every voice
  for i = 0, 15 do
    engine.amp_slew(i, slew_rate)
  end
end

function set_note(synth_num, value)
  notes[synth_num] = value
  --also reset the cents value here too
  if not z_tuning then
    params:set("cents" .. synth_num + 1, 0)
  end
  local hz_value = MusicUtil.note_num_to_freq(notes[synth_num])
  engine.hz(synth_num, hz_value)
  engine.hz_lag(synth_num, 0.005)
  if scale_toggle then
    --do nothing
  end
  if not scale_toggle then
    edit = synth_num
  end
  if norns.crow.connected() then
    set_crow_note(synth_num, hz_value)
  end
  screen_dirty = true
end

function set_freq(synth_num, value)
  engine.hz(synth_num, value)
  engine.hz_lag(synth_num, 0.005)
  edit = synth_num
  screen_dirty = true
end

function set_vol(synth_num, value)
  engine.vol(synth_num, value * 0.2)
  edit = synth_num

  -- update displayed sine value
  local s_id = (synth_num + 1)
  sliders[s_id] = math.floor(util.linlin(0.0, 1.0, 0, 32, value))

  screen_dirty = true
end

function tune(synth_num, value)
  --calculate new tuned value from cents value + midi note
  --https://music.stackexchange.com/questions/17566/how-to-calculate-the-difference-in-cents-between-a-note-and-an-arbitrary-frequen
  local detuned_freq = (math.pow(10, value / 3986)) * MusicUtil.note_num_to_freq(notes[synth_num])
  --round to 2 decimal points
  detuned_freq = math.floor((detuned_freq) * 10 / 10)
  set_freq(synth_num, detuned_freq)
  edit = synth_num
  screen_dirty = true
end

function set_env(synth_num, value)
  --env_name, env_bias, attack, decay
  params:set("env_bias" .. synth_num, envs[value][2])
  params:set("attack" .. synth_num, envs[value][3])
  params:set("decay" .. synth_num, envs[value][4])
end

function env_formatter(value)
  local env_name = envs[value][1]
  return (env_name)
end

function crow_out_formatter(num)
  --return the list as a string
  local crow_output = table.concat(crow_outs[num], ",")
  return (crow_output)
end

function eoc_delay_formatter(value)
  local eoc_delay_ms = value/100
  return (eoc_delay_ms)
end

function sample_bitrate_formatter(value)
  local sample_bitrate_preset = sample_bitrates[value][1]
  return (sample_bitrate_preset)
end

function set_sample_bitrate(synth_num, value)
  params:set("smpl_rate" .. synth_num, sample_bitrates[value][2])
  params:set("bit_depth" .. synth_num, sample_bitrates[value][3])
  screen_dirty = true
end

function set_fm_index(synth_num, value)
  engine.fm_index(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_amp_atk(synth_num, value)
  engine.amp_atk(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_amp_rel(synth_num, value)
  engine.amp_rel(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_amp_eoc_delay(synth_num, value)
  engine.eoc_delay(synth_num, value/100)
  edit = synth_num
  screen_dirty = true
end

function set_env_bias(synth_num, value)
  engine.env_bias(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_bit_depth(synth_num, value)
  engine.bit_depth(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_sample_rate(synth_num, value)
  engine.sample_rate(synth_num, value)
  edit = synth_num
  screen_dirty = true
end

function set_synth_pan(synth_num, value)
  engine.pan(synth_num, value)
  screen_dirty = true
end

function pan_formatter(value)
  if value == -1 then
    text = "right"
  elseif value == 0 then
    text = "middle"
  elseif value == 1 then
    text = "left"
  end
  return (text)
end

function global_pan_formatter(value)
  if value == 0 then
    text = "middle"
  elseif value == 1 then
    text = "left/right"
  end
  return (text)
end

function set_active()
  if control_toggle then
    -- set params
    if params_select == 0 then
      current_state = {5, 15, 2, 2, 2}
    elseif params_select == 1 then
      current_state = {5, 2, 15, 2, 2}
    elseif params_select == 2 then
      current_state = {5, 2, 2, 15, 2}
    elseif params_select == 3 then
      current_state = {5, 2, 2, 2, 15}
    end
  else
    -- set sliders active
    current_state = {15, 2, 2, 2, 2}
  end
  screen_dirty = true
end

function set_global_pan(value)
  -- pan position on the bus, 0 is middle, 1 is l/r
  if value == 0 then
    for i = 1, 16 do
      set_synth_pan(i, 0)
      params:set("pan" .. i, 0)
    end
  elseif value == 1 then
    for i = 1, 16 do
      if i % 2 == 0 then
        --even, pan right
        set_synth_pan(i, 1)
        params:set("pan" .. i, 1)
      elseif i % 2 == 1 then
        --odd, pan left
        set_synth_pan(i, -1)
        params:set("pan" .. i, -1)
      end
    end
  end
end

--update when a cc change is detected
m = midi.connect()
m.event = function(data)
local d = midi.to_msg(data)
  if d.type == "note_on" then
    params:set("root_note", d.note)
  end
  screen_dirty = true
end

function enc(n, delta)
  if n == 1 then
    if control_toggle then
      --select params line 0-3
      params_select = (params_select + delta) % 4
    end
  elseif n == 2 then
    if control_toggle then
      if params_select == 0 then
        -- increment the note value with delta
        if not z_tuning then
          params:set("note" .. edit + 1, params:get("note" .. edit + 1) + delta)
          local synth_num =  edit + 1
          local hz_value = MusicUtil.note_num_to_freq(notes[synth_num])
          if norns.crow.connected() then
            set_crow_note(synth_num, hz_value)
          end
        end
      elseif  params_select == 1 then
        --envl
        params:set("env" .. edit + 1, params:get("env" .. edit + 1) + delta)
      elseif  params_select == 2 then
        --smpl
        params:set("sample_bitrate" .. edit + 1, params:get("sample_bitrate" .. edit + 1) + (delta))
      elseif  params_select == 3 then
        --pan
        params:set("pan" .. edit + 1, params:get("pan" .. edit + 1) + (delta))
      end
    elseif not control_toggle then
      --navigate up/down the list of sliders
      --accum wraps around 0-15
      accum = (accum + delta) % 16
      --edit is the slider number
      edit = accum
    end
  elseif n == 3 then
    if control_toggle then
      if params_select == 0 then
        --detun
        if not z_tuning then
          params:set("cents" .. edit + 1, params:get("cents" .. edit + 1) + delta)
        end
      elseif  params_select == 1 then
        --envd
        params:set("eoc_delay" .. edit + 1, params:get("eoc_delay" .. edit + 1) + delta)
      elseif  params_select == 2 then
        --fmind
        params:set("fm_index" .. edit + 1, params:get("fm_index" .. edit + 1) + delta)
      elseif  params_select == 3 then
        --crow
        params:set("crow_outputs", params:get("crow_outputs") + delta)
      end
    elseif not control_toggle then
      --current slider amplitude
      local new_v = sliders[edit + 1] + (delta * 2)
      local amp_value = util.linlin(0, 32, 0.0, 1.0, new_v)
      params:set("vol" .. edit + 1, amp_value)
    end
  end
  screen_dirty = true
end

function key(n, z)
  if n == 2 and z == 1 then
    control_toggle = not control_toggle
  elseif n == 3 and z == 1 then
    -- TODO lfos?
  end
  screen_dirty = true
end

function redraw()
  screen.aa(1)
  screen.line_width(2.0)
  screen.clear()

  for i = 0, 15 do
    if i == edit then
      screen.level(current_state[1])
    else
      screen.level(2)
    end
    screen.move(32 + i * 4, 62)
    screen.line(32 + i * 4, 60 - sliders[i + 1])
    screen.stroke()
  end
  screen.level(10)
  screen.line(32 + step * 4, 68)
  screen.stroke()
  --display current values
  if z_tuning then
    screen.move(0, 5)
    screen.level(2)
    screen.text("ztun:")
    screen.move(24, 5)
    --get the tuning state
    tuning_table = z_tuning.get_tuning_state()
    if tuning_table and tuning_table.selected_tuning then
      selected_tuning_value = tuning_table.selected_tuning
    end
    --clip to fit on the screen
    screen.text(string.sub(selected_tuning_value, 1, 8))
    screen.move(62, 5)
    screen.level(2)
    screen.text("root:")
    screen.move(89, 5)
    screen.text((string.format("%.2f", params:get("zt_root_freq"))) .. "hz")
  else
    screen.move(0, 5)
    screen.level(2)
    screen.text("note: ")
    screen.level(current_state[2])
    screen.move(24, 5)
    screen.text(MusicUtil.note_num_to_name(params:get("note" .. edit + 1), true) .. " ")
    screen.move(62, 5)
    screen.level(2)
    screen.text("dtun:")
    screen.level(current_state[2])
    screen.move(89, 5)
    screen.text(params:get("cents" .. edit + 1) .. " cents")
  end
  screen.move(0, 12)
  screen.level(2)
  screen.text("envl:")
  screen.level(current_state[3])
  screen.move(24, 12)
  screen.text(env_formatter(params:get("env" .. edit + 1)))
  screen.level(2)
  screen.move(62, 12)
  screen.text("envd:")
  screen.level(current_state[3])
  screen.move(89, 12)
  screen.text(eoc_delay_formatter(params:get("eoc_delay" .. edit + 1)) .. " s")
  screen.move(0, 19)
  screen.level(2)
  screen.text("smpl:")
  screen.level(current_state[4])
  screen.move(24, 19)
  screen.text(sample_bitrate_formatter(params:get("sample_bitrate" .. edit + 1)))
  screen.level(2)
  screen.move(62, 19)
  screen.text("fmind:")
  screen.level(current_state[4])
  screen.move(89, 19)
  screen.text(params:get("fm_index" .. edit + 1))
  screen.move(0, 26)
  screen.level(2)
  screen.text("pan:")
  screen.level(current_state[5])
  screen.move(24, 26)
  screen.text(pan_formatter(params:get("pan" .. edit + 1)))
  screen.level(2)
  screen.move(62, 26)
  screen.text("crow:")
  screen.level(current_state[5])
  screen.move(89, 26)
  if norns.crow.connected() then
    screen.text(crow_out_formatter(params:get("crow_outputs")))
  else
    screen.text("none")
  end
  screen.update()
end
