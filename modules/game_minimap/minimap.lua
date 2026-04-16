-- @ Minimap
minimapWidget  = nil
minimapWindow  = nil
local otmm     = true
local fullmapView = false
local oldZoom  = nil
local oldPos   = nil
local minimapButton = nil

local DEFAULT_MINIMAP_HEIGHT = 200
local MIN_ZOOM = -1
local virtualFloor = 7

-- ============================================================
-- Helpers
-- ============================================================

local function isInHorizontalPanel()
    if not minimapWindow then return false, nil end
    local parent = minimapWindow:getParent()
    if not parent then return false, nil end
    local parentId = parent:getId()
    if string.find(parentId, "horizontal") then
        return true, parentId
    end
    return false, parentId
end

function adjustMainPanelHeight()
    local panel = modules.game_interface.getMainRightPanel()
    if not panel then return end
    local height = 0
    for _, child in pairs(panel:getChildren()) do
        if child:isVisible() then
            height = height + child:getHeight()
        end
    end
    if height > 0 then
        panel:setHeight(height)
    end
end

local function refreshFloorIndicator()
    if not minimapWindow then return end
    local floorPos = minimapWindow:getChildById('floorPosition')
    if floorPos then
        floorPos:setImageClip(virtualFloor * 14 .. ' 0 14 67')
    end
end

local function onPositionChange()
    local player = g_game.getLocalPlayer()
    if not player then return end
    local pos = player:getPosition()
    if not pos then return end
    if minimapWidget and not minimapWidget:isDragging() then
        if not fullmapView then
            minimapWidget:setCameraPosition(pos)
        end
        minimapWidget:setCrossPosition(pos)
    end
    virtualFloor = pos.z
    refreshFloorIndicator()
end

-- ============================================================
-- Controller
-- ============================================================

mapController = Controller:new()
mapController:setUI('minimap', modules.game_interface.getMainRightPanel())

function mapController:onInit()
    minimapWindow = self.ui
    minimapWidget = minimapWindow:recursiveGetChildById('minimap')

    -- Esconde botões internos padrão do widget Minimap
    local btns = {'floorUpButton', 'floorDownButton', 'zoomInButton', 'zoomOutButton', 'resetButton'}
    for _, name in ipairs(btns) do
        local btn = minimapWidget:getChildById(name)
        if btn then btn:hide() end
    end

    -- Restaurar altura salva
    local savedHeight = g_settings.getNumber('minimapHeight', DEFAULT_MINIMAP_HEIGHT)
    if savedHeight >= 100 then
        minimapWindow:setHeight(savedHeight)
    end

    -- Zoom via scroll do mouse
    minimapWidget.onMouseWheel = function(widget, mousePos, direction)
        if direction == MouseWheelUp then
            zoom(true)
        elseif direction == MouseWheelDown then
            zoom(false)
        end
        return true
    end

    -- Salvar altura ao redimensionar e atualizar painel
    minimapWindow.onResize = function(widget, oldSize, newSize)
        g_settings.set('minimapHeight', widget:getHeight())
        local inHoriz = isInHorizontalPanel()
        if not inHoriz then
            adjustMainPanelHeight()
        end
    end

    -- Handler para quando o minimap é movido entre painéis
    local lastParentId = nil
    minimapWindow.onParentChange = function(self2, oldParent, newParent)
        if not self2 then return end
        local newId = newParent and newParent:getId() or ""
        if lastParentId == newId then return end
        lastParentId = newId
        if newId == "gameMainRightPanel" then
            addEvent(function() adjustMainPanelHeight() end, 100)
        end
    end

    -- Sincronizar estado do botão lateral
    minimapWindow.onOpen = function()
        if minimapButton then minimapButton:setOn(true) end
    end
    minimapWindow.onClose = function()
        if minimapButton then minimapButton:setOn(false) end
    end

    -- Registrar botão no mainpanel
    if modules.game_mainpanel then
        minimapButton = modules.game_mainpanel.addToggleButton(
            'minimapButton', tr('Map View'),
            '/images/topbuttons/minimap',
            toggle, false
        )
    end
end

function mapController:onGameStart()
    mapController:registerEvents(g_game, {
        onChangeWorldTime = onChangeWorldTime
    })
    mapController:registerEvents(LocalPlayer, {
        onPositionChange = onPositionChange
    }):execute()

    g_minimap.clean()
    local minimapFile = '/minimap'
    local loadFnc = nil
    if otmm then
        minimapFile = minimapFile .. '.otmm'
        loadFnc = g_minimap.loadOtmm
    else
        minimapFile = minimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'
        loadFnc = g_map.loadOtcm
    end
    if g_resources.fileExists(minimapFile) then
        loadFnc(minimapFile)
    end
    minimapWidget:load()

    minimapWindow:open()
    if minimapButton then minimapButton:setOn(true) end
end

function mapController:onGameEnd()
    g_settings.set('minimapHeight', minimapWindow:getHeight())
    if otmm then
        g_minimap.saveOtmm('/minimap.otmm')
    else
        g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
    end
    minimapWidget:save()
end

function mapController:onTerminate()
    if minimapButton then
        minimapButton:destroy()
        minimapButton = nil
    end
end

-- ============================================================
-- Hora do servidor
-- ============================================================

function onChangeWorldTime(hour, minute)
    local position = math.floor((124 / (24 * 60)) * ((hour * 60) + minute))
    local centerMap = minimapWindow:getChildById('centerMap')
    if centerMap then
        centerMap:setImageClip(position .. ' 0 34 34')
    end
    mapController:scheduleEvent(function()
        local nextH = hour
        local nextM = minute + 12
        if nextM >= 60 then nextH = nextH + 1; nextM = nextM - 60 end
        onChangeWorldTime(nextH % 24, nextM)
    end, 30000, 'dayTime')
end

-- ============================================================
-- Funções públicas
-- ============================================================

function toggle()
    if not minimapWindow then return end
    if minimapWindow:isVisible() then
        minimapWindow:close()
    else
        minimapWindow:open()
    end
end

function isVisible()
    return minimapWindow and minimapWindow:isVisible()
end

function onClose()
    if minimapButton then minimapButton:setOn(false) end
end

function zoom(bool)
    if not minimapWidget then return end
    if bool then
        minimapWidget:zoomIn()
    else
        if minimapWidget:getZoom() > MIN_ZOOM then
            minimapWidget:zoomOut()
        end
    end
end

function floor(bool)
    if not minimapWidget then return end
    if bool then
        minimapWidget:floorUp(1)
        if virtualFloor > 0 then virtualFloor = virtualFloor - 1 end
    else
        minimapWidget:floorDown(1)
        if virtualFloor < 15 then virtualFloor = virtualFloor + 1 end
    end
    refreshFloorIndicator()
end

function center()
    if not minimapWidget then return end
    minimapWidget:reset()
    local player = g_game.getLocalPlayer()
    if player then
        virtualFloor = player:getPosition().z
        refreshFloorIndicator()
    end
end

function openCyclopediaMap()
    if g_game.getClientVersion() >= 1310 then
        modules.game_cyclopedia.toggle('map')
    else
        toggleFullMap()
    end
end

function toggleFullMap()
    if not minimapWidget then return end
    if not fullmapView then
        fullmapView = true
        minimapWindow:hide()
        minimapWidget:setParent(modules.game_interface.getRootPanel())
        minimapWidget:fill('parent')
    else
        fullmapView = false
        minimapWidget:setParent(minimapWindow)
        minimapWidget:fill('parent')
        minimapWidget:setMargin(15, 4, 4, 4)
        minimapWindow:show()
    end
    local z = oldZoom or 0
    local pos = oldPos or minimapWidget:getCameraPosition()
    oldZoom = minimapWidget:getZoom()
    oldPos = minimapWidget:getCameraPosition()
    minimapWidget:setZoom(z)
    minimapWidget:setCameraPosition(pos)
end

-- Move o minimap para outro painel
function move(panel, height, index)
    if not panel then return end
    local panelId = panel:getId()
    local isHorizontal = string.find(panelId, "horizontal") ~= nil
    minimapWindow:setParent(panel)
    if height and height > 0 then
        minimapWindow:setHeight(height)
    elseif isHorizontal then
        minimapWindow:setHeight(DEFAULT_MINIMAP_HEIGHT)
    end
    minimapWindow:show()
    return minimapWindow
end

-- Retorna o minimap ao painel principal direito
function returnToMainPanel()
    if not minimapWindow then return end
    local parent = modules.game_interface.getMainRightPanel()
    if not parent then return end
    minimapWindow:setParent(parent)
    parent:moveChildToIndex(minimapWindow, 1)
    minimapWindow:show()
    addEvent(function() adjustMainPanelHeight() end, 50)
end

function getMiniMapUi()
    return minimapWidget
end

function extendedView(mode)
    -- compatibilidade com game_interface
end
