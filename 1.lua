local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ==================== LOADING GUI ====================

local loadingGui = PlayerGui:FindFirstChild("LoadingGui")

if loadingGui then

    print("[INFO] Waiting for LoadingGui to disappear...")

    while loadingGui and loadingGui.Parent do
        task.wait(0.05)
    end

    print("[INFO] Loading GUI disappeared")
    task.wait(5)
end

print("[INFO] Game fully loaded")

-- ==================== WEBSOCKET ====================

local WS_URL = "ws://192.168.1.14:8080"

local ws = nil
local wsConnected = false

local sentFail = false
local sentRecovered = false

local serverState = {
    Check = false,
    Busy = true,
    ReceivedFirstState = false
}

local function setupWebSocket()

    local success, result = pcall(function()

        if WebSocket and WebSocket.connect then
            return WebSocket.connect(WS_URL)
        elseif WebSocket and WebSocket.Connect then
            return WebSocket.Connect(WS_URL)
        end

        error("No websocket support")
    end)

    if success and result then

        ws = result
        wsConnected = true

        print("[WS] Connected")

        ws.OnMessage:Connect(function(msg)

            print("[WS RAW]", msg)

            local ok, data = pcall(function()
                return HttpService:JSONDecode(msg)
            end)

            if not ok then
                warn("[WS] Invalid JSON")
                return
            end

            print("[WS JSON]", HttpService:JSONEncode(data))

            -- STATE
            if data.type == "state" and data.state then

                if data.state.Check ~= nil then
                    serverState.Check = data.state.Check
                end

                if data.state.Busy ~= nil then
                    serverState.Busy = data.state.Busy
                end

                serverState.ReceivedFirstState = true

                print(
                    "[STATE]",
                    "Check =", tostring(serverState.Check),
                    "Busy =", tostring(serverState.Busy)
                )
            end

            -- EVENTS
            if data.type == "event" then

                print("[EVENT]", data.event)

                if data.event == "check_true" then
                    serverState.Check = true
                end

                if data.event == "busy_false" then
                    serverState.Busy = false
                end
            end
        end)

        ws.OnClose:Connect(function()

            wsConnected = false
            ws = nil

            warn("[WS] Disconnected")

            task.wait(5)

            setupWebSocket()
        end)

        -- READY
        task.delay(0.5, function()

            if ws and wsConnected then

                pcall(function()

                    ws:Send(HttpService:JSONEncode({
                        type = "client_ready",
                        client = "roblox"
                    }))

                end)
            end
        end)

        -- HEARTBEAT
        task.spawn(function()

            while ws and wsConnected do

                task.wait(10)

                pcall(function()

                    ws:Send(HttpService:JSONEncode({
                        type = "heartbeat",
                        user = player.Name,
                        time = os.time()
                    }))

                end)
            end
        end)

    else

        warn("[WS] Failed:", tostring(result))

        task.wait(5)

        setupWebSocket()
    end
end

setupWebSocket()

-- ==================== SEND WS ====================

local function sendWS(payload)

    if not ws or not wsConnected then
        warn("[WS] Not connected")
        return
    end

    pcall(function()

        ws:Send(HttpService:JSONEncode(payload))

    end)
end

local function sendLose(username)

    sendWS({
        Lose = username
    })

    sendWS({
        instaFail = true
    })
end

local function sendRecovered(username)

    sendWS({
        Recovered = username
    })

    sendWS({
        instaFail = false
    })
end

local function sendDupeTrue()

    sendWS({
        Dupe = true
    })
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

-- ==================== GUI ====================

local guiPath = player:WaitForChild("PlayerGui")
    :WaitForChild("Lobby")
    :WaitForChild("PostOffice")
    :WaitForChild("Menus")
    :WaitForChild("ReceivePackages")
    :WaitForChild("ScrollingFrame")

-- ==================== NETWORK ====================

local remote = ReplicatedStorage
    :WaitForChild("NetworkingContainer")
    :WaitForChild("DataRemote")

local idValue = ReplicatedStorage
    :WaitForChild("IdentifiersContainer")
    :WaitForChild("RF_59fb8da4c771fdd9e7348c3e113b4939ec60069b536a2ff0e2dd4f9e857a6611_S")
    .Value

local staticString = "\218\231*\223\237\226@\151\148Y@7%\190&\159"

-- ==================== REJOIN ====================

local function kickAndRejoin()

    print("[INFO] Sending Dupe=true")

    sendDupeTrue()

    print("[INFO] Waiting for initial state")

    while not serverState.ReceivedFirstState do

        task.wait(0.5)

        print("[WAIT] No state received yet")
    end

    print("[INFO] Waiting for Check=true and Busy=false")

    while true do

        task.wait(0.5)

        print(
            "[WAITING]",
            "Check =", tostring(serverState.Check),
            "Busy =", tostring(serverState.Busy)
        )

        if serverState.Check == true
        and serverState.Busy == false then
            break
        end
    end

    print("[INFO] Conditions met")

    player:Kick("Retrying...")

    while true do

        local success, err = pcall(function()

            TeleportService:Teleport(game.PlaceId, player)

        end)

        if not success then
            warn("[TP ERROR]", err)
        end

        task.wait(5)
    end
end

-- ==================== MAIN LOOP ====================

print("[INFO] Waiting for websocket")

while not wsConnected do
    task.wait(0.5)
end

print("[INFO] Main loop started")

while task.wait(0.2) do

    if not wsConnected then
        continue
    end

    local leaderstats = player:FindFirstChild("leaderstats")
    local gems = leaderstats and leaderstats:FindFirstChild("Gems")

    -- SUCCESS
    if gems and gems.Value == 10000000 then

        if not sentRecovered then

            sentRecovered = true

            pcall(function()
                sendRecovered(player.Name)
            end)

            print("[SUCCESS] 10M reached")
        end

        kickAndRejoin()

        break
    end

    -- FAIL
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

            if frameFound then
                break
            end

            task.wait(0.5)

            elapsed += 0.5
        end

        if gems and gems.Value == 10000000 then

            print("[INFO] Already recovered")

        elseif not frameFound then

            sentFail = true

            print("[FAIL] No frames found")

            pcall(function()
                sendLose(player.Name)
            end)

        else

            print("[INFO] Frames detected")
        end
    end

    -- REMOTE
    for _, child in ipairs(guiPath:GetChildren()) do

        if child:IsA("Frame") then

            local args = {
                {
                    {
                        idValue,
                        staticString,
                        child.Name
                    }
                }
            }

            remote:FireServer(unpack(args))
        end
    end
end
