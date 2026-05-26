-- SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Wait for loading GUI
local loadingGui = PlayerGui:FindFirstChild("LoadingGui")
if loadingGui then
    print("[INFO] Waiting for LoadingGui to disappear...")
    loadingGui:GetPropertyChangedSignal("Parent"):Wait()
    while loadingGui.Parent do task.wait(0.05) end
    print("[INFO] Loading GUI disappeared → verifying 5s stable")
    task.wait(5)
end

print("[INFO] Game fully loaded")

-- WebSocket Configuration
local WS_URL = "ws://192.168.1.14:8080"
local ws = nil
local wsConnected = false

-- Prevent duplicate requests
local sentFail = false
local sentRecovered = false

-- Server state (initialize with proper defaults)
local serverState = { 
    Check = true,  -- Default should be true based on your server's initial state
    Busy = false,
    ReceivedFirstState = false  -- Track if we've received initial state
}

-- ==================== WEBSOCKET SETUP ====================
local function setupWebSocket()
    local success, result = pcall(function()
        return WebSocket.connect(WS_URL)
    end)

    if success and result then
        ws = result
        wsConnected = true
        print("[WS] Connected to server")

        ws.OnMessage:Connect(function(msg)
            print("[WS] Received:", msg)
            
            -- Parse server messages
            local success, data = pcall(function()
                return HttpService:JSONDecode(msg)
            end)
            
            if success and data then
                if data.type == "state" then
                    -- Update server state
                    if data.state then
                        serverState.Check = data.state.Check or false
                        serverState.Busy = data.state.Busy or false
                        serverState.ReceivedFirstState = true
                        print(string.format("[STATE] Check=%s, Busy=%s", 
                            tostring(serverState.Check), 
                            tostring(serverState.Busy)))
                    end
                elseif data.type == "event" then
                    print("[EVENT]", data.event)
                    if data.event == "check_true" then
                        serverState.Check = true
                        serverState.Busy = false
                        print("[STATE] Check set to TRUE via event")
                    elseif data.event == "dupe_changed" then
                        if data.Dupe ~= nil then
                            serverState.Check = not data.Dupe
                        end
                    end
                elseif data.type == "heartbeat_ack" then
                    print("[WS] Heartbeat OK")
                end
            end
        end)

        ws.OnClose:Connect(function()
            wsConnected = false
            ws = nil
            print("[WS] Disconnected, reconnecting in 5s...")
            task.wait(5)
            setupWebSocket()
        end)

        -- Send initial handshake
        task.wait(0.5)
        if ws and wsConnected then
            pcall(function()
                ws:Send(HttpService:JSONEncode({ type = "client_ready", client = "roblox" }))
            end)
        end

        -- Start heartbeat
        task.spawn(function()
            while wsConnected and ws do
                task.wait(10)
                if ws and wsConnected then
                    pcall(function()
                        ws:Send(HttpService:JSONEncode({ type = "heartbeat", user = player.Name, time = os.time() }))
                    end)
                end
            end
        end)

        return true
    else
        print("[WS] Failed to connect:", tostring(result))
        task.wait(5)
        setupWebSocket()
        return false
    end
end

-- ==================== SEND VIA WEBSOCKET ====================
local function sendWS(payload)
    if ws and wsConnected then
        pcall(function()
            ws:Send(HttpService:JSONEncode(payload))
        end)
    else
        print("[WS] Not connected, cannot send")
    end
end

-- Add user to Fails
local function sendLose(username)
    sendWS({ Lose = username })
    sendWS({ instaFail = true })
end

-- Remove user from Fails
local function sendRecovered(username)
    sendWS({ Recovered = username })
    sendWS({ instaFail = false })
end

-- Dupe = true via WS
local function sendDupeTrue()
    sendWS({ Dupe = true })
end

-- ==================== POSITION ====================
task.spawn(function()
    local char = player.Character or player.CharacterAdded:Wait()
    while true do
        char = player.Character or player.CharacterAdded:Wait()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = CFrame.new(-458, 244, -68)
            break
        end
        task.wait(1)
    end
end)

-- ==================== WAIT FOR GUI ====================
local guiPath = player:WaitForChild("PlayerGui")
    :WaitForChild("Lobby")
    :WaitForChild("PostOffice")
    :WaitForChild("Menus")
    :WaitForChild("ReceivePackages")
    :WaitForChild("ScrollingFrame")

-- ==================== NETWORKING ====================
local remote = ReplicatedStorage:WaitForChild("NetworkingContainer"):WaitForChild("DataRemote")
local idValue = ReplicatedStorage:WaitForChild("IdentifiersContainer"):WaitForChild(
    "RF_59fb8da4c771fdd9e7348c3e113b4939ec60069b536a2ff0e2dd4f9e857a6611_S"
).Value
local staticString = "\218\231*\223\237\226@\151\148Y@7%\190&\159"

-- ==================== KICK FUNCTION ====================
local function kickAndRejoin()
    print("[KICK] Sending Dupe=true and kicking...")
    sendDupeTrue()
    player:Kick("Retrying...")

    task.spawn(function()
        task.wait(0.3)
        print("[INFO] Waiting for Check=true AND Busy=false...")
        
        -- Wait for initial state if not received yet
        while not serverState.ReceivedFirstState do
            print("[WAIT] Waiting for first server state...")
            task.wait(1)
        end
        
        -- Now wait for Check=true and Busy=false
        local waitStart = os.time()
        while true do
            task.wait(0.5)
            print(string.format("[CHECK] Check=%s, Busy=%s, Elapsed=%ds", 
                tostring(serverState.Check), 
                tostring(serverState.Busy),
                os.time() - waitStart))
            
            if serverState.Check == true and serverState.Busy == false then
                print("[INFO] ✅ Conditions met, teleporting back")
                break
            end
            
            -- Timeout after 60 seconds and teleport anyway
            if os.time() - waitStart > 60 then
                print("[WARN] Timeout waiting for Check=true, teleporting anyway")
                break
            end
        end

        -- Teleport back
        while true do
            local success, err = pcall(function() 
                TeleportService:Teleport(game.PlaceId, player) 
            end)
            if not success then
                print("[ERROR] Teleport failed:", err)
            end
            task.wait(5)
        end
    end)
end

-- Connect WebSocket first
setupWebSocket()

-- Wait for WebSocket to be connected before main loop
print("[INFO] Waiting for WebSocket connection...")
while not wsConnected do
    task.wait(0.5)
end
print("[INFO] WebSocket connected, starting main loop")

-- ==================== MAIN LOOP ====================
while task.wait() do
    -- Wait for WebSocket to be ready
    if not wsConnected then
        task.wait(1)
        goto continue
    end
    
    local leaderstats = player:FindFirstChild("leaderstats")
    local gems = leaderstats and leaderstats:FindFirstChild("Gems")

    -- SUCCESS CONDITION
    if gems and gems.Value == 10000000 then
        if not sentRecovered then
            sentRecovered = true
            pcall(function()
                sendRecovered(player.Name)
            end)
            print("[SUCCESS] 10M gems reached, sending recovered")
        end
        kickAndRejoin()
        break
    end

    -- FAIL CONDITION
    if not sentFail then
        local frameFound = false
        local elapsed = 0
        
        while elapsed < 20 do
            for _, child in ipairs(guiPath:GetChildren()) do
                if child:IsA("Frame") then
                    frameFound = true
                    break
                end
            end
            if frameFound then break end
            task.wait(0.5)
            elapsed = elapsed + 0.5
        end
        
        local leaderstats = player:FindFirstChild("leaderstats")
        local gems = leaderstats and leaderstats:FindFirstChild("Gems")
        
        if gems and gems.Value == 10000000 then
            print("[INFO] Already at 10M, not reporting failure")
        elseif not frameFound then
            sentFail = true
            print("[FAIL] No frames found after 20s, reporting failure")
            pcall(function()
                sendLose(player.Name)
            end)
        else
            print("[INFO] Frames found within 20s, skipping fail report")
        end
    end

    -- REMOTE FIRING LOGIC
    for _, child in ipairs(guiPath:GetChildren()) do
        if child:IsA("Frame") then
            local args = { { { idValue, staticString, child.Name } } }
            remote:FireServer(unpack(args))
        end
    end
    
    ::continue::
end
