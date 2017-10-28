-- VUMeter.lua
-- module 'jive.audio.VUMeter'

--[[

	Derived from the file VUMeter.lua included in the Squeezeplay software
	package.

	Modifications include:

	* Provision of a variety of meter calibrations, all of which are aligned
	  to the existing VUMeter display graphics. (No change required to
	  existing artwork).
	* Ability to cycle through available calibrations by touching screen twice
	  within a short time period. (Same action as cycling through normal Now
	  Playing screens, except that two quick taps cycle through the
	  calibrations instead.)
	* Removal of redundant code associated with the 'VUMeter' style, which
	  appears to have been geared towards an unused stacked bar/segment display.

--]]


local oo            = require("loop.simple")
local math          = require("math")

local Framework     = require("jive.ui.Framework")
local Icon          = require("jive.ui.Icon")
local Surface       = require("jive.ui.Surface")
local Timer         = require("jive.ui.Timer")
local Widget        = require("jive.ui.Widget")

local decode        = require("squeezeplay.decode")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("audio.decode")

local FRAME_RATE    = jive.ui.FRAME_RATE

local logUI         = require("jive.utils.log").logger("squeezeplay.ui")
local Font          = require("jive.ui.Font")
local EVENT_CONSUME	= jive.ui.EVENT_CONSUME
local EVENT_UNUSED	= jive.ui.EVENT_UNUSED

--[[ ### not implemented
-- to implement persistence
local appletManager = appletManager
local tonumber      = tonumber
--]]

-- for debugging
local pairs, setmetatable = pairs, setmetatable


module(...)
oo.class(_M, Icon)


-- VUMeter - available RMS maps
-- First one is close to that provided by the shipping version of VUMeter.lua,
-- but uses all available meter positions

local RMS_MAPS = {
	{
		LEGEND = '',
		RMS_MAP =  {
			    0,    2,   10,   26,   54,   94,  149,  219,  306,  410,  534,  678,
			  842, 1029, 1238, 1472, 1729, 2012, 2321, 2657, 3021, 3413, 3833, 4284,
			 4765
		}
	},
	{
		LEGEND = 'ref: 0dB FS',
		RMS_MAP =  {
			    0,   81,  471,  667,  897, 1161, 1459, 1792, 2158, 2559, 2994, 3463,
			 3965, 4502, 5073, 5678, 6318, 6991, 7698, 8439, 9215,10024,10868,11746,
			14158
		}
	},
	{
		LEGEND = 'ref: -3dB FS',
		RMS_MAP =  {
			    0,   40,  235,  333,  448,  581,  730,  896, 1079, 1280, 1497, 1731,
			 1983, 2251, 2537, 2839, 3159, 3495, 3849, 4220, 4607, 5012, 5434, 5873,
			 7079
		}
	},
	{
		LEGEND = 'ref: -6dB FS',
		RMS_MAP =  {
			    0,   20,  118,  167,  224,  290,  365,  448,  540,  640,  748,  866,
			  991, 1126, 1268, 1420, 1579, 1748, 1925, 2110, 2304, 2506, 2717, 2936,
			 3540
		}
	},
	{
		LEGEND = 'ref: -9dB FS',
		RMS_MAP =  {
			    0,   10,   59,   83,  112,  145,  182,  224,  270,  320,  374,  433,
			  496,  563,  634,  710,  790,  874,  962, 1055, 1152, 1253, 1359, 1468,
			 1770
		}
	},
	{
		LEGEND = 'ref: -12dB FS',
		RMS_MAP =  {
			    0,    5,   29,   42,   56,   73,   91,  112,  135,  160,  187,  216,
			  248,  281,  317,  355,  395,  437,  481,  527,  576,  627,  679,  734,
			  885
		}
	},
	{
		LEGEND = 'ref: -15dB FS',
		RMS_MAP =  {
			    0,    3,   15,   21,   28,   36,   46,   56,   67,   80,   94,  108,
			  124,  141,  159,  177,  197,  218,  241,  264,  288,  313,  340,  367,
			  442
		}
	},
	{
		LEGEND = 'ref: -18dB FS',
		RMS_MAP =  {
			    0,    1,    7,   10,   14,   18,   23,   28,   34,   40,   47,   54,
			   62,   70,   79,   89,   99,  109,  120,  132,  144,  157,  170,  184,
			  221
		}
	},
	{
		LEGEND = 'ref: -21dB FS',
		RMS_MAP =  {
			    0,    1,    4,    5,    7,    9,   11,   14,   17,   20,   23,   27,
			   31,   35,   40,   44,   49,   55,   60,   66,   72,   78,   85,   92,
			  111
		}
	},
	{
		LEGEND = 'ref: -24dB FS',
		RMS_MAP =  {
			    0,    1,    2,    3,    4,    5,    6,    7,    8,   10,   12,   14,
			   15,   18,   20,   22,   25,   27,   30,   33,   36,   39,   42,   46,
			   55
		}
	},

}

--[[

  Notes on Mean square tables

	decode:vumeter delivers mean sum of squares for each of left & right
	channels, based on 7 most significant bits of samples. Mean sum of squares
	is rounded down.

	0 dB FS (sine) is indicated by mean sum of squares 8064.5, (which would be
	rounded down to 8064). Being 127 x 127 / 2.

	+3 dB FS gives 16129, being 127 x 127. (Alternatively 0 dB FS (square)).

	The meter scale (*) is essentially linear in 'voltage', except the bottom
	& top positions. Position 18 (zero based) represents 100. It is fitted
	well by:

		VI = POS × 4.596682 + 17.259723

	in the linear region.

	(*) 'UNOFFICIAL/VUMeter/vu_analog_25seq_b.png'

	Each position has been assigned a bucket of values, so as to capture a
	range within +/- 0.5 of a position. Positions 1 and 24 have been given
	somewhat lower/higher range limits to reflect the non-linearity of the
	meter scale at these limits.

	Note that 20 dB down from full scale corresponds to mean squares of 81.

	This is the 0 dB table:

	POS  +--  Nominal --+ +------ Lower limit ------+
	---  --VI-- ----dB--- --VI-- ----dB--- -Mean squ-

	 0     0.00             0.00                  0
	 1    21.86 -13.21 dB  10.00 -20.00 dB       81

	 2    26.45 -11.55 dB  24.15 -12.34 dB      471
	 3    31.05 -10.16 dB  28.75 -10.83 dB      667
	 4    35.65  -8.96 dB  33.35  -9.54 dB      897
	 5    40.24  -7.91 dB  37.94  -8.42 dB     1161
	 6    44.84  -6.97 dB  42.54  -7.42 dB     1459
	 7    49.44  -6.12 dB  47.14  -6.53 dB     1792
	 8    54.03  -5.35 dB  51.73  -5.72 dB     2158
	 9    58.63  -4.64 dB  56.33  -4.98 dB     2559
	10    63.23  -3.98 dB  60.93  -4.30 dB     2994
	11    67.82  -3.37 dB  65.52  -3.67 dB     3463
	12    72.42  -2.80 dB  70.12  -3.08 dB     3965
	13    77.02  -2.27 dB  74.72  -2.53 dB     4502
	14    81.61  -1.76 dB  79.31  -2.01 dB     5073
	15    86.21  -1.29 dB  83.91  -1.52 dB     5678
	16    90.81  -0.84 dB  88.51  -1.06 dB     6318
	17    95.40  -0.41 dB  93.10  -0.62 dB     6991
	18   100.00   0.00 dB  97.70  -0.20 dB     7698
	19   104.60   0.39 dB 102.30   0.20 dB     8439
	20   109.19   0.76 dB 106.90   0.58 dB     9215
	21   113.79   1.12 dB 111.49   0.94 dB    10024
	22   118.39   1.47 dB 116.09   1.30 dB    10868
	23   122.98   1.80 dB 120.69   1.63 dB    11746

	24   141.25   3.00 dB 128.00   2.44 dB    14158

	With the exception of the endpoints, the above table can be derived from
	the square law:

	Mean Squares = 8064.5 * ( (POS - 0.5 + zero_offset) / (18 + zero_offset) )^2
	where zero_offset = 3.754822 ( = 17.259723 / 4.596682 ).

	8064.5 is 0dB FS (sine), and is assigned to position 18 (0 VU).
	The adjustment of 0.5 establishes a lower bucket limit for each position.
	zero_offset is the (negative) POS at which the meter would record zero if
	it were linear all the way down.

	The first table is a special case. It has been derived using the power law:
	Mean Squares = 5277 * (POS/25)^2.5
	This is a close approximation to the table that ships with the original
	VUMeter.lua, except that it has been extended to cover all available
	positions. 5277 is the value that aligns the Mean Square value at
	position 18 with that of the original table.

	'Quiet' music - e.g. at -18 dB and lower, may not register at all at some
	of the higher reference points. That is a consequence of the limited range
	of the meter faceplate. Classical music may often fall into this category.
	Arguably one should abandon the 'classic VU meter' scale in favour of, say,
	a linear decibel scale. Or expand its range to go to -30 dB.

	Also, at these low levels, the Mean Squares calculation becomes less
	reliable, because it has been based on the high 7 bits of each sample.
	15 bits would improve accuracy.


	It might be interesting to return M & S values, as well as L & R.

--]]

function __init(self, style)
	local obj = oo.rawnew(self, Icon(style))

	obj.style = style

	obj.cap = { 0, 0 }

	obj:addAnimation(function() obj:reDraw() end, FRAME_RATE)

	-- data store for our params
	obj.legend = {}
	-- set up RMS map table to use, fetches from persistent store if required
	_prepare_map()
	-- prepare UI - traps 'go_now_playing_action'
	_setupCalibrationUI(obj)

	logUI:info('VUMeter - modified version')

	return obj

end

--[[

  Remark:

	We do have some local style info that could be stored in a skin. But that
	would require modifying the skin code. Anyway, we are only ever called
	from the 'WQVGA' small & large screens, and there is no difference in
	metrics for the actual vumeter display.

--]]

function _skin(self)

	Icon._skin(self)

	-- original script anticipated an NP style of 'vumeter_analog' for the
	-- analogue VUMeter, and, apparently, 'vumeter' for an (unimplemented) bar
	-- display
	if self.style != "vumeter_analog" then
		logUI:warn('Now Playing Style \'', self.style, '\' is not recognized')
	end

	-- the 25 frame analogue scale + pointer image 
	self.bgImg = self:styleImage("bgImg")

	-- we could hunt down items in the skin and reuse - but not much use as
	-- we only want one size anyway
	self.legend.font = Font:load("fonts/FreeSans.ttf", 12)
	--self.legend.font = Font:load("fonts/FreeSansBold.ttf", 12)

	local WHITE      = 0xE7E7E7FF
	--local OFFWHITE   = 0xDCDCDCFF
	local BACKGROUND_TEAL_ALPHA = 0x00BEBEC0
	self.legend.fg = WHITE
	-- the margin that we place around the legend text on its background
	self.legend.xborder = 3
	self.legend.yborder = 1
	self.legend.bg = BACKGROUND_TEAL_ALPHA

end


-- module level variables that hold the calibration currently in force

-- positive integer from 1 .. #RMS_MAPS 
local current_map
-- holds the text legend and the RMS_MAP
-- set up by _prepare_map()
-- must be set up before calling _layout & draw
local current_LEGEND
local current_RMS_MAP


-- sets up appropriate values for current RMS map & legend, as determined by
-- 'current_map'
-- ### to do: load/save 'current_map' value from/to persistent settings store
-- to survive restart/reboot

-- called by __init, and by _goNowPlayingHandler when cycling through
-- calibrations
function _prepare_map()

	if not current_map then

--[[ ### not the right place for this, revisit
		-- first time call - load from persistent storage
		local settings = getSettings()
		if settings and settings['activeMap'] and tonumber(settings['activeMap']) then
			current_map = tonumber(settings['activeMap'])
		end
		-- should not happen, but...
--]]
		if not current_map then
			current_map = 1
		end
	end

	if (current_map < 1) or (current_map > #RMS_MAPS) then
		current_map = 1
	end
	-- load up the current RMS map from our table
	current_LEGEND  = RMS_MAPS[current_map].LEGEND
	current_RMS_MAP = RMS_MAPS[current_map].RMS_MAP

--[[ ### too busy, not a good place to do it, revisit
	-- save to persistent storage
	local settings = getSettings()
	if settings and (settings['activeMap'] ~= current_map) then
		settings['activeMap'] = current_map
		storeSettings()
	end
--]]

end


function _layout(self)
	local x,y,w,h = self:getBounds()
	local l,t,r,b = self:getPadding()

	-- When used in NP screen _layout gets called with strange values
	if (w <= 0 or w > 480) and (h <= 0 or h > 272) then
		return
	end

	self.x1 = x
	self.x2 = x + (w / 2)
	self.y = y
	self.w = w / 2
	self.h = h


	-- prepare legend - displays 0 VU reference level on transparent background

	-- help out garbage collector
	if self.legend.backgroundImg then
		self.legend.backgroundImg:release()
		self.legend.backgroundImg = nil
	end
	if self.legend.textImg then
		self.legend.textImg:release()
		self.legend.textImg = nil
	end

	-- we only want a legend if there is, indeed, a legend available
	if (current_LEGEND and (current_LEGEND:len() != 0)) then

		-- draw the text
		self.legend.textImg = Surface:drawText(self.legend.font, self.legend.fg, current_LEGEND)
		local calw, calh = self.legend.textImg:getSize()

		-- make a slightly larger, and reasonably transparent, background
		-- rectangle to put it on
		calw = calw + self.legend.xborder + self.legend.xborder
		calh = calh + self.legend.yborder + self.legend.yborder
		self.legend.backgroundImg = Surface:newRGBA(calw, calh)
		self.legend.backgroundImg:filledRectangle(0, 0, calw - 1, calh - 1, self.legend.bg)

		-- ideally we would lay the text on the background, and have just one
		-- image, but I can't figure how to have the text overwrite the
		-- background's alpha

		-- we'll position it at the top centre of the visualizer area, leaving
		-- a two pixel border above
		self.legend.y = y + 2
		self.legend.x = x + (w - calw) / 2
		-- top right hand side
		--self.legend.x = x + w - calw - 2

	end

end


function draw(self, surface)

	local sampleAcc = decode:vumeter()

	--logUI:debug("L: ", sampleAcc[1], " R: ", sampleAcc[2])

	_drawMeter(self, surface, sampleAcc, 1, self.x1, self.y, self.w, self.h)
	_drawMeter(self, surface, sampleAcc, 2, self.x2, self.y, self.w, self.h)

	-- draw legend, but only if we have one
	if self.legend.backgroundImg then
		-- legend background first, which has some alpha
		self.legend.backgroundImg:blit(surface, self.legend.x, self.legend.y)
		-- then legend text, offset by the built-in border
		self.legend.textImg:blit(surface, self.legend.x + self.legend.xborder,
											self.legend.y + self.legend.yborder)
	end

end


function _drawMeter(self, surface, sampleAcc, ch, x, y, w, h)

	-- self.bgimg is expected hold an image consisting of 25 successive frames
	-- corresponding to the VUMeter faceplate with an appropriately positioned
	-- pointer (25 positions)
	-- width of each frame must match width available in layout (half screen
	-- width)

	local val = 1
	for i = #current_RMS_MAP, 1, -1 do
		if sampleAcc[ch] > current_RMS_MAP[i] then
			val = i
			break
		end
	end
	-- zero-base the range of allowed pointer positions
	val = val - 1

	if val >= self.cap[ch] then
		-- wind the pointer straight up to the reading 
		self.cap[ch] = val

	elseif self.cap[ch] > 0 then
		-- slowly unwind the pointer down to the reading, once per animation
		-- frame
		self.cap[ch] = self.cap[ch] - 1
	end

	if ch == 1 then
		self.bgImg:blitClip(self.cap[ch] * w, y, w, h, surface, x, y)
	else
		self.bgImg:blitClip(self.cap[ch] * w, y, w, h, surface, x, y)
	end

end


-- Code to subvert the 'screen touch' action that cycles through the
-- Now Playing screens.

-- Two successive touches within 375ms will cycle through our collection of
-- 0 VU reference points. Otherwise a touch will be dealt with normally,
-- although delayed by 375ms.

--[[

  Remarks:

	The Now Playing app wraps the VUMeter widget in a 'button' that emits a
	'go_now_playing' action when the display is touched. That action is caught
	by the Now Playing window, which executes 'toggleNPScreenStyle'.

	The 'go_now_playing' action can also be emitted in response to 'key' or IR
	events.

	Ideally we would modify the action by adding an 'actionListener' to our
	VUMeter widget. But the VUMeter widget never sees it (possibly because it
	doesn't have focus).

	We work around that by adding an 'actionListener' at the framework level,
	having a higher priority. We engage/disengage that listener according to
	whether our widget is showing. We know it is showing if its 'visible'
	property is true. (The widget's default '_event' handler sets/resets its
	'visible' property in response to EVENT_SHOW & EVENT_HIDE events.)

	It is possible that there may be more than one VUMeter in existence at a
	given time, for example when 'transitioning' on starting to play a new
	track. We only act for the 'latest' VUMeter.

--]]

-- the handle of the framework level listener
local gnpActionListenerHandle = nil
-- the VUMeter instance that will receive our attention
local currentVUMeter          = nil

-- timer to trigger deferred 'go_now_playing' action
-- a one-shot timer firing after 375ms, unless stopped before then
-- gnpActionFromTimer == true tells us that the timer is the source
local gnpActionFromTimer      = false
local gnpActionDispatchTimer  =
			Timer(	375,
					function()
						logUI:debug('timer expired - emitting deferred GNP action')
						gnpActionFromTimer = true
						Framework:pushAction("go_now_playing")
		 			end,
					true
			)

-- the go_now_playing framework level action listener
function _goNowPlayingHandler(self, event)
	-- we set 'self' to 'nil', not a widget object as might be expected

	-- is this our 'timer generated' deferred gnp action ? if so, just pass on
	if gnpActionFromTimer then
		logUI:debug('pass through deferred GNP action')
		-- belt & braces - should already be stopped
		gnpActionDispatchTimer:stop()
		gnpActionFromTimer = false
		return EVENT_UNUSED
		-- Remark:
		--  Normally we will navigate away from the VUMeter widget at this
		--  point. But not always (e.g. if this is only selected NP style).
		--  Were it otherwise, we might actually remove the handler here.
	end

	if not (currentVUMeter and currentVUMeter.visible) then
		-- disengaged state
		-- this does not mean that our VUMeter window has gone for good, it
		--  could be under a context window, or a screen saver, for example.
		-- we simply pass the action on, while continuing to monitor
		logUI:debug('not on show - pass through GNP action')
		gnpActionDispatchTimer:stop()
		gnpActionFromTimer = false
		return EVENT_UNUSED
	end

	-- is this a gnp action received within our 375ms window ? if so, we
	--  cycle through our calibration maps
	if gnpActionDispatchTimer:isRunning() then

		logUI:debug('second GNP action - within 375ms')
		gnpActionDispatchTimer:stop()
		gnpActionFromTimer = false

		-- move on to the next map
		current_map = (current_map % #RMS_MAPS) + 1
		_prepare_map()

		-- VUMeter must be reskinned
		currentVUMeter:reSkin()

		return EVENT_CONSUME

	end

	-- the gnp action is the first of possibly two screen touches
	-- do nothing, but start timer for next action
	logUI:debug('first GNP action - starting timer')
	gnpActionFromTimer = false
	gnpActionDispatchTimer:start()
	return EVENT_CONSUME

end


-- to be called from VUMeter init
function _setupCalibrationUI( obj )

	-- create a global listener to trap the 'go_now_playing' action, if not
	-- already created
	if not gnpActionListenerHandle then
		-- provide 'nil' as our object - this is not specific to any widget
		--  instance
		-- priority '-1' to ensure gets called before widgets
		gnpActionListenerHandle =
			Framework:addActionListener("go_now_playing", nil, _goNowPlayingHandler, -1)
	end

	-- set/reset the VUMeter widget of interest. The assumption is that once
	-- VUMeter:__init has been called, an earlier VUMeter widget is of no
	-- further interest. That widget could hang around for a while, e.g.
	-- during a transition.

	-- a side effect is that an otherwise 'defunct' VUMeter widget will not be
	-- garbage collected as soon as it might otherwise have been, because
	-- 'currentVUMeter' will still hold a reference to it

	currentVUMeter = obj

	-- debug/verify VUMeter widget garbage collection
	--widget_record(obj)

end


--[[ ### leave out for now, not the best way to do this
-- Functions to save & restore persistent settings. As we are not an 'app'
-- we use the 'NowPlaying' app's settings store. A bit rude, perhaps.
function getSettings()
	local vuMeterSettings
	local NowPlaying = appletManager:getAppletInstance("NowPlaying")
	if NowPlaying then
		local npsettings = NowPlaying:getSettings()
		if not npsettings['customVUMeterSettings'] then
			npsettings['customVUMeterSettings'] = {}
			npsettings['customVUMeterSettings']['info'] = 'This table was made by a customized VUMeter.lua, and can be deleted.'
		end
		vuMeterSettings = npsettings['customVUMeterSettings']
	end
	return vuMeterSettings
end

function storeSettings()

	local NowPlaying = appletManager:getAppletInstance("NowPlaying")
	if NowPlaying then
		local npsettings = NowPlaying:getSettings()
		NowPlaying:storeSettings()
	end
end
--]]


-- for verifying widget garbage collection
local widget_ref   = 1
local widgets_seen = setmetatable({}, {__mode = "k"})
function widget_record(obj)
	widgets_seen[obj] = widget_ref
	widget_ref = widget_ref + 1
	for k, v in pairs(widgets_seen) do
		logUI:debug('widget_ref: ', v,' ', k)
	end
end


--[[

=head1 LICENCE


** This file is a modified version of the file VUMeter.lua distributed within
   Logitech's Squeezeplay software package.


** The following modifications have been made to that file:

	Provision of a variety of meter calibrations
    Ability to select from the available calibrations
    Removal of redundant code associated with the 'VUMeter' style


** This file is distributed under the following BSD-style license: 

Modifications copyright 2012, Martin Williams <martinr.williams@gmail.com>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The name of the author may not be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
OF THE POSSIBILITY OF SUCH DAMAGE.


** This file incorporates work covered by the following copyright and
   permission notice: 
 
Copyright 2010 Logitech. All Rights Reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Logitech nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL LOGITECH, INC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
--]]

