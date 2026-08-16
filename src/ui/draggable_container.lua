-- Draggable UIBox container for Balatro HUD elements (based on BalaLib/SystemClock)
local DraggableContainer = UIBox:extend()

function DraggableContainer:init(args)
    args = args or {}
    args.config = args.config or {}
    args.can_drag = (args.can_drag == nil) and true or args.can_drag

    Moveable.init(self, args)

    self.states.drag.can = args.can_drag
    self.states.collide.can = true
    self.draw_layers = {}

    self.definition = args.definition
    self.config = args.config

    if args.config.h_popup then
        self.config.h_popup_config = self.config.h_popup_config or { align = self.T.y > G.ROOM.T.h / 2 and 'tm' or 'bm' }
        self.config.h_popup_config.parent = self
    end
    args.config.major = args.config.major or args.config.parent or self

    self:set_alignment({
        major = args.config.major or G,
        type = args.config.align or args.config.type or '',
        bond = args.config.bond or 'Strong',
        offset = args.config.offset or { x = 0, y = 0 },
        lr_clamp = args.config.lr_clamp
    })
    self:set_role{
        xy_bond = args.config.xy_bond or 'Weak',
        r_bond = args.config.r_bond or 'Weak',
        wh_bond = args.config.wh_bond or 'Weak',
        scale_bond = args.config.scale_bond or 'Weak'
    }

    self.states.collide.can = ((args.config.can_collide ~= nil) and args.config.can_collide) or self.states.collide.can
    self.parent = self.config.parent

    self:set_parent_child(self.definition, nil)
    self.Mid = self.Mid or self.UIRoot
    self:calculate_xywh(self.UIRoot, self.T)

    self.T.w = self.UIRoot.T.w
    self.T.h = self.UIRoot.T.h
    self.UIRoot:set_wh()
    self.UIRoot:set_alignments()

    self.VT.x = (args.VT and args.VT.x) or self.T.x
    self.VT.y = (args.VT and args.VT.y) or self.T.y
    self.VT.w, self.VT.h = self.T.w, self.T.h

    if self.alignment and self.alignment.lr_clamp then self:lr_clamp() end

    self.UIRoot:initialize_VT(true)

    self.zoom = (args.zoom ~= nil) and args.zoom or (args.config and args.config.zoom)
    if self.zoom then self.UIRoot:set_zoom(true, true) end

    if args.config.instance_type == 'POPUP' and not self.created_on_pause then
        self.created_on_pause = true
        self.UIRoot:set_created_on_pause(true, true)
    end

    self.attention_text = 'SpotifyHUD'

    if args.config.instance_type then
        table.insert(G.I[args.config.instance_type], self)
    else
        table.insert(G.I.UIBOX, self)
    end
end

function DraggableContainer:hover()
    if self.states.drag.can then
        self:juice_up(0.04, 0.02)
        play_sound('chips1', math.random() * 0.1 + 0.55, 0.15)
        if self.zoom then
            self.UIRoot:set_hover_state(true, true)
        end
    end
    UIBox.hover(self)
end

function DraggableContainer:stop_hover()
    if self.zoom then
        self.UIRoot:set_hover_state(false, true)
    end
    UIBox.stop_hover(self)
end

function DraggableContainer:drag()
    if self.zoom then
        self.UIRoot:set_drag_state(true, true)
    end
    UIBox.drag(self)
end

function DraggableContainer:stop_drag()
    if self.zoom then
        self.UIRoot:set_drag_state(false, true)
    end
    UIBox.stop_drag(self)
    if G.SPOTIFY and G.SPOTIFY.config then
        G.SPOTIFY.config.current.hud_x = self.T.x
        G.SPOTIFY.config.current.hud_y = self.T.y
        G.SPOTIFY.config.save()
    end
end

return DraggableContainer
