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

local latestCheck = false
local latestBusy = true

local sentFail = false
local sentRecovered = false

local function setupWebSocket()

    local success, result = pcall(function()
        return WebSocket.connect(WS_URL)
    end)

    if success and result then

        ws = result
        wsConnected = true

        print("[WS] Connected")

        ws.OnMessage:Connect(function(msg)

            print("[WS] Received:", msg)

            local ok, data = pcall(function()
                return HttpService:JSONDecode(msg)
            end)

            if ok and data then

                if data.type == "state" and data.data then

                    latestCheck = data.data.Check
                    latestBusy = data.data.Busy

                    print(
                        "[STATE]",
                        "Check =", latestCheck,
                        "Busy =", latestBusy
                    )
                end
            end
        end)

        ws.OnClose:Connect(function()

            wsConnected = false
            ws = nil

            print("[WS] Disconnected")

            task.wait(5)

            setupWebSocket()
        end)

        -- heartbeat
        task.spawn(function()

            while wsConnected and ws do

                task.wait(10)

                pcall(function()

                    ws:Send(HttpService:JSONEncode({
                        type = "heartbeat",
                        time = os.time()
                    }))

                end)
            end
        end)

    else

        warn("[WS] Failed:", result)

        task.wait(5)

        setupWebSocket()
    end
end

setupWebSocket()

-- ==================== SEND WS ====================

local function sendWS(payload)

    if ws and wsConnected then

        pcall(function()

            ws:Send(HttpService:JSONEncode(payload))

        end)
    end
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

    player:Kick("Retrying...")

    print("[INFO] Waiting for Check=true and Busy=false")

    while true do

        task.wait(0.5)

        print(
            "[WAITING]",
            "Check =", latestCheck,
            "Busy =", latestBusy
        )

        if latestCheck == true and latestBusy == false then
            break
        end
    end

    print("[INFO] Conditions met")

    while true do

        local success, err = pcall(function()

            TeleportService:Teleport(game.PlaceId, player)

        end)

        if not success then
            warn(err)
        end

        task.wait(5)
    end
end

-- ==================== MAIN LOOP ====================

while task.wait(0.2) do

    local leaderstats = player:FindFirstChild("leaderstats")

    local gems = leaderstats and leaderstats:FindFirstChild("Gems")

    -- SUCCESS

    if gems and gems.Value == 10000000 then

        if not sentRecovered then

            sentRecovered = true

            pcall(function()

                sendRecovered(player.Name)

            end)
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

            print("[INFO] Already at 10M")

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

    -- FIRE REMOTE

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
