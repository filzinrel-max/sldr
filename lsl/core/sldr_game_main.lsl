//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config.lslh"
#include "../include/ddr_debug.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_state_machine.lslh"
#include "ddr_animation_bridge.lslh"

integer gListenHandle = 0;
integer gLoadingChart = FALSE;
integer gGameplayActive = FALSE;
integer gControlsCaptured = FALSE;
key gActivePlayer = NULL_KEY;
integer gSessionActive = FALSE;
integer gHasShownMenu = FALSE;
string gLastPlayRequestSignature = "";
string gPlayingMediaPath = "";
integer gDirectionHeldMask = 0;
vector gSitTargetOffset = <0.0, 0.0, 0.0>;
rotation gSitTargetRot = ZERO_ROTATION;

integer ddrIsOwner(key agentId)
{
    return agentId == llGetOwner();
}

integer ddrIsActivePlayer(key agentId)
{
    return gSessionActive && agentId == gActivePlayer;
}

integer ddrIsAuthorizedActor(key agentId)
{
    return ddrIsOwner(agentId) || ddrIsActivePlayer(agentId);
}

key ddrCurrentSitter()
{
    return llAvatarOnSitTarget();
}

integer ddrSetupSitTarget()
{
    llSitTarget(gSitTargetOffset, gSitTargetRot);
    llSetSitText(DDR_SIT_TEXT);
    llSetTouchText(DDR_SIT_TEXT);
    llSetClickAction(CLICK_ACTION_SIT);
    return TRUE;
}

integer ddrBootShowSplash()
{
    gState = DDR_STATE_SPLASH;
    gStateEnteredAt = ddrNow();
    return ddrSetMediaUrl(ddrBuildScreenUrl(DDR_STATE_SPLASH, "status=idle"));
}

integer ddrGoMainMenu(string reason, string extraQuery)
{
    gHasShownMenu = TRUE;
    string query = extraQuery;
    if (gPlayingSongId != "")
    {
        if (query != "")
        {
            query += "&";
        }
        query += "song=" + llEscapeURL(gPlayingSongId);
    }
    if (gPlayingDifficulty != "")
    {
        if (query != "")
        {
            query += "&";
        }
        query += "difficulty=" + llEscapeURL(gPlayingDifficulty);
    }
    if (query != "")
    {
        query += "&";
    }
    query += "ts=" + (string)llGetUnixTime();
    return ddrTransition(DDR_STATE_MAIN_MENU, reason, query);
}

integer ddrInputControlMask()
{
    return
        CONTROL_LEFT |
        CONTROL_RIGHT |
        CONTROL_UP |
        CONTROL_DOWN |
        CONTROL_FWD |
        CONTROL_BACK |
        CONTROL_ROT_LEFT |
        CONTROL_ROT_RIGHT;
}

integer ddrDirectionHeldMask(integer held)
{
    integer mapped = 0;

    if ((held & (CONTROL_LEFT | CONTROL_ROT_LEFT)) != 0)
    {
        mapped = mapped | CONTROL_LEFT;
    }
    if ((held & (CONTROL_RIGHT | CONTROL_ROT_RIGHT)) != 0)
    {
        mapped = mapped | CONTROL_RIGHT;
    }
    if ((held & (CONTROL_UP | CONTROL_FWD)) != 0)
    {
        mapped = mapped | CONTROL_UP;
    }
    if ((held & (CONTROL_DOWN | CONTROL_BACK)) != 0)
    {
        mapped = mapped | CONTROL_DOWN;
    }
    return mapped;
}

integer ddrSyncIdleAnimationFromHeld(integer heldMask)
{
    if (!gSessionActive)
    {
        ddrIdleAnimationStop();
        return TRUE;
    }

    if (heldMask != 0)
    {
        ddrIdleAnimationStop();
    }
    else
    {
        ddrIdleAnimationStart();
    }
    return TRUE;
}

integer ddrInputStartCapture()
{
    if (!ddrHasPermission(PERMISSION_TAKE_CONTROLS))
    {
        return FALSE;
    }
    llTakeControls(ddrInputControlMask(), TRUE, FALSE);
    gControlsCaptured = TRUE;
    gDirectionHeldMask = 0;
    ddrSyncIdleAnimationFromHeld(gDirectionHeldMask);
    return TRUE;
}

integer ddrInputStopCapture()
{
    if (gControlsCaptured)
    {
        llReleaseControls();
    }
    gControlsCaptured = FALSE;
    gDirectionHeldMask = 0;
    ddrSyncIdleAnimationFromHeld(gDirectionHeldMask);
    return TRUE;
}

integer ddrSendRuntimeMessage(integer code, string payload)
{
    llMessageLinked(LINK_SET, code, payload, NULL_KEY);
    return TRUE;
}

integer ddrSendRuntimeReset()
{
    return ddrSendRuntimeMessage(DDR_LM_RUNTIME_RESET, "");
}

integer ddrSendRuntimeDebug(integer enabled)
{
    if (enabled)
    {
        return ddrSendRuntimeMessage(DDR_LM_RUNTIME_DEBUG, "1");
    }
    return ddrSendRuntimeMessage(DDR_LM_RUNTIME_DEBUG, "0");
}

integer ddrSendRuntimeStatusRequest()
{
    return ddrSendRuntimeMessage(DDR_LM_RUNTIME_STATUS, "");
}

integer ddrSendRuntimeControl(integer held, integer changedMask)
{
    return ddrSendRuntimeMessage(
        DDR_LM_RUNTIME_CONTROL,
        (string)held + "|" + (string)changedMask
    );
}

integer ddrPlayAnimationsForPresses(integer held, integer changedMask)
{
    if (!ddrHasPermission(PERMISSION_TRIGGER_ANIMATION))
    {
        return FALSE;
    }

    if ((changedMask & CONTROL_LEFT) != 0 && (held & CONTROL_LEFT) != 0)
    {
        ddrPlayLaneAnimation(DDR_LANE_LEFT);
    }
    if ((changedMask & CONTROL_DOWN) != 0 && (held & CONTROL_DOWN) != 0)
    {
        ddrPlayLaneAnimation(DDR_LANE_DOWN);
    }
    if ((changedMask & CONTROL_UP) != 0 && (held & CONTROL_UP) != 0)
    {
        ddrPlayLaneAnimation(DDR_LANE_UP);
    }
    if ((changedMask & CONTROL_RIGHT) != 0 && (held & CONTROL_RIGHT) != 0)
    {
        ddrPlayLaneAnimation(DDR_LANE_RIGHT);
    }
    return TRUE;
}

string ddrReadMediaCurrentUrl()
{
    list values = llGetPrimMediaParams(DDR_MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL]);
    if (llGetListLength(values) > 0)
    {
        string mediaUrl = llList2String(values, 0);
        if (mediaUrl != "")
        {
            return mediaUrl;
        }
    }
    return gCurrentMediaUrl;
}

string ddrDecodeUrlComponent(string encoded)
{
    string plusFixed = llDumpList2String(llParseStringKeepNulls(encoded, ["+"], []), "%20");
    return llUnescapeURL(plusFixed);
}

string ddrUrlQueryValue(string url, string keyName)
{
    integer queryStart = llSubStringIndex(url, "?");
    if (queryStart < 0)
    {
        return "";
    }

    string query = llGetSubString(url, queryStart + 1, -1);
    integer hashIndex = llSubStringIndex(query, "#");
    if (hashIndex >= 0)
    {
        query = llGetSubString(query, 0, hashIndex - 1);
    }
    if (query == "")
    {
        return "";
    }

    string keyLower = llToLower(keyName);
    list pairs = llParseStringKeepNulls(query, ["&"], []);
    integer i = 0;
    integer count = llGetListLength(pairs);
    for (; i < count; ++i)
    {
        string pair = llList2String(pairs, i);
        if (pair == "")
        {
            jump next_pair;
        }

        integer eqIndex = llSubStringIndex(pair, "=");
        string keyEncoded = pair;
        string valueEncoded = "";
        if (eqIndex >= 0)
        {
            keyEncoded = llGetSubString(pair, 0, eqIndex - 1);
            valueEncoded = llGetSubString(pair, eqIndex + 1, -1);
        }

        if (llToLower(ddrDecodeUrlComponent(keyEncoded)) == keyLower)
        {
            return ddrDecodeUrlComponent(valueEncoded);
        }
@next_pair;
    }
    return "";
}

integer ddrStopGameplayLocal()
{
    gLoadingChart = FALSE;
    gGameplayActive = FALSE;
    ddrInputStopCapture();
    ddrSendRuntimeReset();
    return TRUE;
}

integer ddrStartSongLoadFromSelection(
    string chartPathOrUrl,
    string songId,
    string songTitle,
    string songArtist,
    string difficulty,
    string mediaPath
)
{
    if (!gSessionActive)
    {
        ddrDebug("PLAY", "session inactive");
        return FALSE;
    }
    if (gLoadingChart || gGameplayActive)
    {
        return FALSE;
    }

    chartPathOrUrl = llStringTrim(chartPathOrUrl, STRING_TRIM);
    if (chartPathOrUrl == "")
    {
        ddrDebug("PLAY", "missing chart path");
        return FALSE;
    }

    difficulty = llStringTrim(difficulty, STRING_TRIM);
    if (difficulty == "")
    {
        difficulty = "Easy";
    }

    songId = llStringTrim(songId, STRING_TRIM);
    if (songId == "")
    {
        songId = "song-unknown";
    }
    songTitle = llStringTrim(songTitle, STRING_TRIM);
    if (songTitle == "")
    {
        songTitle = songId;
    }
    songArtist = llStringTrim(songArtist, STRING_TRIM);
    if (songArtist == "")
    {
        songArtist = "Unknown Artist";
    }

    gPlayingSongId = songId;
    gPlayingSongTitle = songTitle;
    gPlayingSongArtist = songArtist;
    gPlayingDifficulty = difficulty;
    gPlayingMediaPath = llStringTrim(mediaPath, STRING_TRIM);

    string chartUrl = ddrJoinUrl(DDR_BASE_URL, ddrEncodePathForUrl(chartPathOrUrl));
    string payload = "{}";
    payload = llJsonSetValue(payload, ["chartUrl"], chartUrl);
    payload = llJsonSetValue(payload, ["songId"], gPlayingSongId);
    payload = llJsonSetValue(payload, ["title"], gPlayingSongTitle);
    payload = llJsonSetValue(payload, ["artist"], gPlayingSongArtist);
    payload = llJsonSetValue(payload, ["difficulty"], gPlayingDifficulty);

    gLoadingChart = TRUE;
    gGameplayActive = FALSE;
    ddrSendRuntimeMessage(DDR_LM_RUNTIME_START, payload);

    if (!ddrInputStartCapture())
    {
        ddrRequestRuntimePermissionsFor(gActivePlayer);
    }

    string loadingQuery =
        "loading=1" +
        "&id=" + llEscapeURL(gPlayingSongId) +
        "&title=" + llEscapeURL(gPlayingSongTitle) +
        "&artist=" + llEscapeURL(gPlayingSongArtist) +
        "&difficulty=" + llEscapeURL(gPlayingDifficulty);
    if (gPlayingMediaPath != "")
    {
        loadingQuery += "&media=" + llEscapeURL(gPlayingMediaPath);
    }
    ddrTransition(DDR_STATE_PLAYING, "load-chart", loadingQuery);
    ddrDebug("PLAY", "request song=" + gPlayingSongId + " diff=" + gPlayingDifficulty + " chart=" + chartPathOrUrl);
    return TRUE;
}

integer ddrTryPlayRequestFromMediaUrl()
{
    if (!gSessionActive || gState != DDR_STATE_MAIN_MENU)
    {
        return FALSE;
    }
    if (gLoadingChart || gGameplayActive)
    {
        return FALSE;
    }

    string mediaUrl = ddrReadMediaCurrentUrl();
    string cmd = llToLower(ddrUrlQueryValue(mediaUrl, "cmd"));
    if (cmd != "play")
    {
        return FALSE;
    }

    string signature = ddrUrlQueryValue(mediaUrl, "req");
    if (signature == "")
    {
        signature = mediaUrl;
    }
    if (signature == gLastPlayRequestSignature)
    {
        return FALSE;
    }
    gLastPlayRequestSignature = signature;

    string chartPath = ddrUrlQueryValue(mediaUrl, "chart");
    string songId = ddrUrlQueryValue(mediaUrl, "song");
    string songTitle = ddrUrlQueryValue(mediaUrl, "title");
    string songArtist = ddrUrlQueryValue(mediaUrl, "artist");
    string difficulty = ddrUrlQueryValue(mediaUrl, "difficulty");
    string mediaPath = ddrUrlQueryValue(mediaUrl, "media");

    if (!ddrStartSongLoadFromSelection(chartPath, songId, songTitle, songArtist, difficulty, mediaPath))
    {
        ddrGoMainMenu("play-request-fail", "error=play-request-failed");
        return FALSE;
    }
    return TRUE;
}

integer ddrFinishGameplay(string scorePayload)
{
    ddrInputStopCapture();
    gLoadingChart = FALSE;
    gGameplayActive = FALSE;
    gLastScorePayload = scorePayload;

    ddrTransition(
        DDR_STATE_SCORE,
        "song-complete",
        "result=" + llEscapeURL(gLastScorePayload)
    );
    return TRUE;
}

integer ddrHandleRuntimeReady(string payload)
{
    gLoadingChart = FALSE;
    gGameplayActive = TRUE;

    string runtimeDifficulty = llJsonGetValue(payload, ["difficulty"]);
    if (runtimeDifficulty != JSON_INVALID && runtimeDifficulty != "")
    {
        gPlayingDifficulty = runtimeDifficulty;
    }
    string runtimeMeter = llJsonGetValue(payload, ["meter"]);
    if (runtimeMeter == JSON_INVALID || runtimeMeter == "")
    {
        runtimeMeter = "0";
    }

    if (!ddrInputStartCapture())
    {
        ddrRequestRuntimePermissionsFor(gActivePlayer);
    }

    string query =
        "loading=0" +
        "&id=" + llEscapeURL(gPlayingSongId) +
        "&title=" + llEscapeURL(gPlayingSongTitle) +
        "&artist=" + llEscapeURL(gPlayingSongArtist) +
        "&difficulty=" + llEscapeURL(gPlayingDifficulty) +
        "&meter=" + runtimeMeter;
    if (gPlayingMediaPath != "")
    {
        query += "&media=" + llEscapeURL(gPlayingMediaPath);
    }
    ddrTransition(DDR_STATE_PLAYING, "chart-ready", query);
    return TRUE;
}

integer ddrHandleRuntimeFail(string reason)
{
    ddrInputStopCapture();
    gLoadingChart = FALSE;
    gGameplayActive = FALSE;

    string query = "";
    if (reason != "")
    {
        query = "error=" + llEscapeURL(reason);
    }
    ddrGoMainMenu("runtime-fail", query);
    return FALSE;
}

integer ddrHandleRuntimeStatus(string payload)
{
    string active = llJsonGetValue(payload, ["active"]);
    string loading = llJsonGetValue(payload, ["loading"]);
    string pendingNotes = llJsonGetValue(payload, ["pendingNotes"]);
    string pendingHolds = llJsonGetValue(payload, ["pendingHolds"]);
    string freeMemory = llJsonGetValue(payload, ["freeMemory"]);
    llOwnerSay(
        "[SLDR] runtime active=" + active +
        " loading=" + loading +
        " pendingNotes=" + pendingNotes +
        " pendingHolds=" + pendingHolds +
        " freeMemory=" + freeMemory
    );
    return TRUE;
}

integer ddrTick()
{
    if (gState == DDR_STATE_SPLASH)
    {
        if (ddrStateAge() >= DDR_SPLASH_SECONDS)
        {
            ddrGoMainMenu("auto", "status=ready");
        }
    }
    else if (gState == DDR_STATE_MAIN_MENU)
    {
        ddrTryPlayRequestFromMediaUrl();
    }
    return TRUE;
}

integer ddrHandleOwnerTouch()
{
    if (!gSessionActive)
    {
        return FALSE;
    }
    if (gState == DDR_STATE_SPLASH)
    {
        ddrGoMainMenu("touch", "");
        return TRUE;
    }
    if (gState == DDR_STATE_MAIN_MENU)
    {
        ddrTryPlayRequestFromMediaUrl();
        return TRUE;
    }
    if (gState == DDR_STATE_SCORE)
    {
        ddrGoMainMenu("touch", "");
        return TRUE;
    }
    return FALSE;
}

integer ddrHandleOwnerCommand(string message)
{
    list tokens = llParseString2List(llStringTrim(message, STRING_TRIM), [" "], []);
    if (llGetListLength(tokens) <= 0)
    {
        return FALSE;
    }

    string cmd = llToLower(llList2String(tokens, 0));
    if (cmd == "debug")
    {
        string mode = llToLower(llList2String(tokens, 1));
        if (mode == "on")
        {
            ddrDebugSet(TRUE);
            ddrSendRuntimeDebug(TRUE);
        }
        else if (mode == "off")
        {
            ddrDebugSet(FALSE);
            ddrSendRuntimeDebug(FALSE);
        }
        return TRUE;
    }

    if (cmd == "menu")
    {
        ddrGoMainMenu("cmd", "");
        return TRUE;
    }
    if (cmd == "reload")
    {
        ddrTransition(DDR_STATE_SPLASH, "reload", "status=loading");
        return TRUE;
    }
    if (cmd == "play")
    {
        // /9919 play <chartPathOrUrl> [difficulty] [songId]
        string chartPath = llList2String(tokens, 1);
        if (chartPath == "")
        {
            return ddrTryPlayRequestFromMediaUrl();
        }

        string difficulty = llList2String(tokens, 2);
        string songId = llList2String(tokens, 3);
        return ddrStartSongLoadFromSelection(chartPath, songId, songId, "", difficulty, "");
    }
    if (cmd == "stop")
    {
        if (gState == DDR_STATE_PLAYING)
        {
            ddrStopGameplayLocal();
            ddrGoMainMenu("stop", "");
            return TRUE;
        }
        return FALSE;
    }
    if (cmd == "status")
    {
        llOwnerSay(
            "[SLDR] state=" + ddrStateName(gState) +
            " session=" + (string)gSessionActive +
            " player=" + (string)gActivePlayer +
            " loading=" + (string)gLoadingChart +
            " gameplayActive=" + (string)gGameplayActive +
            " sitOffset=" + (string)gSitTargetOffset +
            " media=" + ddrReadMediaCurrentUrl() +
            " freeMemory=" + (string)llGetFreeMemory()
        );
        ddrSendRuntimeStatusRequest();
        return TRUE;
    }
    if (cmd == "sitoffset")
    {
        if (llGetListLength(tokens) < 4)
        {
            llOwnerSay("[SLDR] usage: /" + (string)DDR_COMMAND_CHANNEL + " sitoffset <x> <y> <z>");
            return FALSE;
        }

        float x = (float)llList2String(tokens, 1);
        float y = (float)llList2String(tokens, 2);
        float z = (float)llList2String(tokens, 3);
        gSitTargetOffset = <x, y, z>;
        ddrSetupSitTarget();
        llOwnerSay("[SLDR] sit offset set to " + (string)gSitTargetOffset + " (re-sit to fully apply)");
        return TRUE;
    }
    if (cmd == "sitreset")
    {
        gSitTargetOffset = DDR_SIT_TARGET_OFFSET;
        gSitTargetRot = DDR_SIT_TARGET_ROT;
        ddrSetupSitTarget();
        llOwnerSay("[SLDR] sit target reset to config offset=" + (string)gSitTargetOffset);
        return TRUE;
    }
    return FALSE;
}

integer ddrEndSession(string reason)
{
    if (!gSessionActive)
    {
        return FALSE;
    }

    ddrDebug("SESSION", "end reason=" + reason + " player=" + (string)gActivePlayer);

    ddrInputStopCapture();
    ddrIdleAnimationStop();
    ddrClearRuntimePermissions();
    ddrSendRuntimeReset();

    gLoadingChart = FALSE;
    gGameplayActive = FALSE;
    gSessionActive = FALSE;
    gActivePlayer = NULL_KEY;
    gLastPlayRequestSignature = "";
    gPlayingMediaPath = "";
    gDirectionHeldMask = 0;

    ddrTransition(DDR_STATE_SPLASH, "session-end", "status=idle");
    return TRUE;
}

integer ddrStartSession(key playerId)
{
    if (playerId == NULL_KEY)
    {
        return FALSE;
    }
    if (gSessionActive && gActivePlayer == playerId)
    {
        return TRUE;
    }
    if (gSessionActive)
    {
        ddrEndSession("swap");
    }

    gSessionActive = TRUE;
    gActivePlayer = playerId;
    gLoadingChart = FALSE;
    gGameplayActive = FALSE;
    gLastPlayRequestSignature = "";
    gPlayingMediaPath = "";
    gDirectionHeldMask = 0;
    ddrInputStopCapture();
    ddrClearRuntimePermissions();
    ddrSendRuntimeReset();

    ddrDebug("SESSION", "start player=" + (string)gActivePlayer);
    if (gHasShownMenu)
    {
        ddrGoMainMenu("session-start", "status=ready");
    }
    else
    {
        ddrTransition(DDR_STATE_SPLASH, "session-start", "status=loading");
    }
    ddrRequestRuntimePermissionsFor(gActivePlayer);
    return TRUE;
}

integer ddrHandleSitChange()
{
    key sitter = ddrCurrentSitter();
    if (!gSessionActive)
    {
        if (sitter != NULL_KEY)
        {
            return ddrStartSession(sitter);
        }
        return FALSE;
    }

    if (sitter == gActivePlayer)
    {
        return FALSE;
    }
    if (sitter == NULL_KEY)
    {
        return ddrEndSession("stand");
    }
    ddrEndSession("swap");
    return ddrStartSession(sitter);
}

integer ddrBoot()
{
    gLoadingChart = FALSE;
    gGameplayActive = FALSE;
    gSessionActive = FALSE;
    gHasShownMenu = FALSE;
    gActivePlayer = NULL_KEY;
    gControlsCaptured = FALSE;
    gLastPlayRequestSignature = "";
    gPlayingMediaPath = "";
    gDirectionHeldMask = 0;
    gSitTargetOffset = DDR_SIT_TARGET_OFFSET;
    gSitTargetRot = DDR_SIT_TARGET_ROT;
    ddrSetupSitTarget();

    if (gListenHandle != 0)
    {
        llListenRemove(gListenHandle);
    }
    gListenHandle = llListen(DDR_COMMAND_CHANNEL, "", NULL_KEY, "");

    llSetTimerEvent(DDR_TICK_SECONDS);
    ddrBootShowSplash();
    ddrDebug("BOOT", "command channel /" + (string)DDR_COMMAND_CHANNEL + " free memory=" + (string)llGetFreeMemory());
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrBoot();
    }

    on_rez(integer startParam)
    {
        llResetScript();
    }

    changed(integer changeMask)
    {
        if (changeMask & CHANGED_OWNER)
        {
            llResetScript();
            return;
        }
        if (changeMask & CHANGED_LINK)
        {
            ddrHandleSitChange();
            ddrSendRuntimeMessage(DDR_LM_RUNTIME_RESCAN_LINKS, "");
        }
    }

    run_time_permissions(integer permissions)
    {
        if (!gSessionActive || llGetPermissionsKey() != gActivePlayer)
        {
            ddrDebug("PERM", "ignored permissions from " + (string)llGetPermissionsKey());
            return;
        }
        ddrHandleRuntimePermissions(permissions);
        ddrSyncIdleAnimationFromHeld(gDirectionHeldMask);
        if (ddrHasPermission(PERMISSION_TAKE_CONTROLS))
        {
            ddrInputStartCapture();
        }
    }

    touch_start(integer detectedCount)
    {
        key toucher = llDetectedKey(0);
        if (ddrIsAuthorizedActor(toucher))
        {
            ddrHandleOwnerTouch();
        }
    }

    listen(integer channel, string name, key speaker, string message)
    {
        if (channel == DDR_COMMAND_CHANNEL && ddrIsAuthorizedActor(speaker))
        {
            ddrHandleOwnerCommand(message);
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_MAIN_READY)
        {
            ddrHandleRuntimeReady(str);
            return;
        }
        if (num == DDR_LM_MAIN_FAIL)
        {
            ddrHandleRuntimeFail(str);
            return;
        }
        if (num == DDR_LM_MAIN_COMPLETE)
        {
            ddrFinishGameplay(str);
            return;
        }
        if (num == DDR_LM_MAIN_STATUS)
        {
            ddrHandleRuntimeStatus(str);
            return;
        }
    }

    control(key controller, integer held, integer changedMask)
    {
        if (ddrIsActivePlayer(controller) && gSessionActive)
        {
            integer logicalHeld = ddrDirectionHeldMask(held);
            integer logicalChanged = logicalHeld ^ gDirectionHeldMask;
            gDirectionHeldMask = logicalHeld;
            ddrSyncIdleAnimationFromHeld(logicalHeld);
            ddrPlayAnimationsForPresses(logicalHeld, logicalChanged);
            if (gState == DDR_STATE_PLAYING && gGameplayActive)
            {
                ddrSendRuntimeControl(logicalHeld, logicalChanged);
            }
        }
    }

    timer()
    {
        ddrTick();
    }
}
