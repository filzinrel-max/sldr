//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config_engine.lslh"
#include "../include/ddr_debug_engine.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_chart_data_runtime.lslh"
#include "ddr_judgement.lslh"

integer gRuntimeActive = FALSE;
integer gRuntimeLoading = FALSE;

string gRuntimeSongId = "";
string gRuntimeSongTitle = "";
string gRuntimeSongArtist = "";
string gRuntimeSongDifficulty = "";

integer gRuntimeSongClockStarted = FALSE;
float gRuntimeSongClockStartAt = 0.0;

// Feedback visuals are delegated to sldr_game_fx.lsl via link messages.
integer ddrFxSend(integer code, string payload)
{
    llMessageLinked(LINK_SET, code, payload, NULL_KEY);
    return TRUE;
}

integer ddrJudgeFeedbackShowJudge(integer judgement) { return ddrFxSend(DDR_LM_FX_JUDGE, (string)judgement); }
integer ddrJudgeFeedbackShowHold(integer holdState) { return ddrFxSend(DDR_LM_FX_HOLD_JUDGE, (string)holdState); }

integer ddrScoreSend(integer code, string payload)
{
    llMessageLinked(LINK_SET, code, payload, NULL_KEY);
    return TRUE;
}

integer ddrScoreReset()
{
    return ddrScoreSend(DDR_LM_SCORE_RESET, "");
}

integer ddrScorePrepareForChart()
{
    integer noteCount = ddrChartNoteCount();
    integer holdCount = ddrChartHoldCount();

    string payload = "{}";
    payload = llJsonSetValue(payload, ["songId"], gRuntimeSongId);
    payload = llJsonSetValue(payload, ["title"], gRuntimeSongTitle);
    payload = llJsonSetValue(payload, ["artist"], gRuntimeSongArtist);
    payload = llJsonSetValue(payload, ["difficulty"], gRuntimeSongDifficulty);
    payload = llJsonSetValue(payload, ["meter"], (string)gChartMeter);
    payload = llJsonSetValue(payload, ["noteCount"], (string)noteCount);
    payload = llJsonSetValue(payload, ["holdCount"], (string)holdCount);
    payload = llJsonSetValue(payload, ["chordTotal"], "0");
    payload = llJsonSetValue(payload, ["offbeatTotal"], "0");
    payload = llJsonSetValue(payload, ["songRadar"], "[0,0,0,0,0]");

    return ddrScoreSend(DDR_LM_SCORE_START, payload);
}

integer ddrScoreApplyNoteJudge(integer judgement, integer noteFlags)
{
    return ddrScoreSend(
        DDR_LM_SCORE_NOTE,
        (string)judgement + "|" + (string)noteFlags
    );
}

integer ddrScoreApplyHoldResult(integer holdState)
{
    return ddrScoreSend(DDR_LM_SCORE_HOLD, (string)holdState);
}

integer ddrRuntimeSend(integer code, string payload)
{
    llMessageLinked(LINK_SET, code, payload, NULL_KEY);
    return TRUE;
}

integer ddrRuntimeClockStart()
{
    gRuntimeSongClockStartAt = ddrNow() + DDR_PLAY_START_DELAY;
    gRuntimeSongClockStarted = TRUE;
    return TRUE;
}

integer ddrRuntimeClockStop()
{
    gRuntimeSongClockStarted = FALSE;
    return TRUE;
}

float ddrRuntimeSongTimeNow()
{
    if (!gRuntimeSongClockStarted)
    {
        return -9999.0;
    }
    return ddrNow() - gRuntimeSongClockStartAt;
}

integer ddrRuntimeSetLaneDown(integer lane, integer isDown)
{
    gLaneDown = llListReplaceList(gLaneDown, [isDown], lane, lane);
    return TRUE;
}

integer ddrRuntimeStopGameplayEx(integer resetScore)
{
    gRuntimeActive = FALSE;
    gRuntimeLoading = FALSE;
    llMessageLinked(LINK_SET, DDR_LM_CHART_CANCEL, "", NULL_KEY);

    ddrRuntimeClockStop();
    ddrChartReset();
    if (resetScore)
    {
        ddrScoreReset();
    }
    ddrFxSend(DDR_LM_FX_RESET, "");
    gPendingNotes = 0;
    gPendingHolds = 0;
    gLaneDown = [FALSE, FALSE, FALSE, FALSE];
    return TRUE;
}

integer ddrRuntimeStopGameplay()
{
    return ddrRuntimeStopGameplayEx(TRUE);
}

integer ddrRuntimeFail(string reason)
{
    ddrRuntimeStopGameplay();
    ddrRuntimeSend(DDR_LM_MAIN_FAIL, reason);
    return TRUE;
}

integer ddrRuntimeRequestChart(string chartUrl)
{
    if (chartUrl == "")
    {
        return FALSE;
    }
    llMessageLinked(LINK_SET, DDR_LM_CHART_LOAD, chartUrl, NULL_KEY);
    return TRUE;
}

integer ddrRuntimeStartFromPayload(string payload)
{
    string chartUrl = llJsonGetValue(payload, ["chartUrl"]);
    if (chartUrl == JSON_INVALID || chartUrl == "")
    {
        return ddrRuntimeFail("missing-chart-url");
    }

    ddrRuntimeStopGameplay();

    gRuntimeSongId = llJsonGetValue(payload, ["songId"]);
    gRuntimeSongTitle = llJsonGetValue(payload, ["title"]);
    gRuntimeSongArtist = llJsonGetValue(payload, ["artist"]);
    if (gRuntimeSongId == JSON_INVALID)
    {
        gRuntimeSongId = "";
    }
    if (gRuntimeSongTitle == JSON_INVALID)
    {
        gRuntimeSongTitle = "";
    }
    if (gRuntimeSongArtist == JSON_INVALID)
    {
        gRuntimeSongArtist = "";
    }
    gRuntimeSongDifficulty = "";

    gRuntimeLoading = TRUE;
    if (!ddrRuntimeRequestChart(chartUrl))
    {
        return ddrRuntimeFail("chart-request-failed");
    }
    return TRUE;
}

integer ddrRuntimeHandleChartReady(string payload)
{
    if (!gRuntimeLoading)
    {
        return FALSE;
    }

    integer seq = (integer)llJsonGetValue(payload, ["seq"]);
    string difficulty = llJsonGetValue(payload, ["difficulty"]);
    integer meter = (integer)llJsonGetValue(payload, ["meter"]);
    float duration = (float)llJsonGetValue(payload, ["duration"]);
    integer notes = (integer)llJsonGetValue(payload, ["notes"]);
    integer holds = (integer)llJsonGetValue(payload, ["holds"]);

    if (difficulty == JSON_INVALID)
    {
        difficulty = "";
    }
    if (!ddrChartSetLoaded(seq, difficulty, meter, duration, notes, holds))
    {
        return ddrRuntimeFail("chart-metadata-failed");
    }

    gRuntimeSongDifficulty = gChartDifficultyName;

    ddrScoreReset();
    ddrScorePrepareForChart();
    ddrJudgeResetForChart();
    ddrFxSend(DDR_LM_FX_RESET, "");
    ddrRuntimeClockStart();

    gRuntimeLoading = FALSE;
    gRuntimeActive = TRUE;
    ddrRuntimeSendReady();
    return TRUE;
}

integer ddrRuntimeSendReady()
{
    string payload = "{}";
    payload = llJsonSetValue(payload, ["difficulty"], gRuntimeSongDifficulty);
    payload = llJsonSetValue(payload, ["meter"], (string)gChartMeter);
    return ddrRuntimeSend(DDR_LM_MAIN_READY, payload);
}

integer ddrRuntimeHandleControl(integer held, integer changedMask)
{
    if (!gRuntimeActive || !gRuntimeSongClockStarted)
    {
        return FALSE;
    }

    float songTime = ddrRuntimeSongTimeNow();

    integer lane = DDR_LANE_LEFT;
    for (; lane < DDR_LANE_COUNT; ++lane)
    {
        integer mask = 0;
        if (lane == DDR_LANE_LEFT)
        {
            mask = CONTROL_LEFT;
        }
        else if (lane == DDR_LANE_DOWN)
        {
            mask = CONTROL_DOWN;
        }
        else if (lane == DDR_LANE_UP)
        {
            mask = CONTROL_UP;
        }
        else
        {
            mask = CONTROL_RIGHT;
        }

        if ((changedMask & mask) != 0)
        {
            integer isDown = ((held & mask) != 0);
            ddrRuntimeSetLaneDown(lane, isDown);
            if (isDown)
            {
                ddrJudgeLanePress(lane, songTime);
            }
            else
            {
                ddrJudgeLaneRelease(lane, songTime);
            }
        }
    }
    return TRUE;
}

integer ddrRuntimeCompleteSong()
{
    ddrScoreSend(DDR_LM_SCORE_FINISH, "");
    ddrRuntimeStopGameplayEx(FALSE);
    return TRUE;
}

integer ddrRuntimeSendStatus()
{
    string payload = "{}";
    payload = llJsonSetValue(payload, ["active"], (string)gRuntimeActive);
    payload = llJsonSetValue(payload, ["loading"], (string)gRuntimeLoading);
    payload = llJsonSetValue(payload, ["pendingNotes"], (string)gPendingNotes);
    payload = llJsonSetValue(payload, ["pendingHolds"], (string)gPendingHolds);
    payload = llJsonSetValue(payload, ["freeMemory"], (string)llGetFreeMemory());
    return ddrRuntimeSend(DDR_LM_MAIN_STATUS, payload);
}

integer ddrRuntimeTick()
{
    if (!gRuntimeActive)
    {
        return FALSE;
    }

    float songTime = ddrRuntimeSongTimeNow();
    if (songTime < -DDR_RENDER_LOOKAHEAD_SECONDS)
    {
        return FALSE;
    }

    if (songTime >= 0.0)
    {
        ddrJudgeAutoMisses(songTime);
        ddrJudgeUpdateHolds(songTime);
    }

    if (ddrJudgeSongComplete(songTime))
    {
        ddrRuntimeCompleteSong();
    }
    return TRUE;
}

integer ddrRuntimeBoot()
{
    gRuntimeActive = FALSE;
    gRuntimeLoading = FALSE;
    ddrRuntimeClockStop();
    ddrChartReset();
    ddrScoreReset();
    gPendingNotes = 0;
    gPendingHolds = 0;
    gLaneDown = [FALSE, FALSE, FALSE, FALSE];
    llSetTimerEvent(DDR_TICK_SECONDS);
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrFxSend(DDR_LM_FX_RESET, "");
        ddrRuntimeBoot();
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
            // Renderer discovery is handled by sldr_game_renderer.lsl.
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_RUNTIME_RESET)
        {
            ddrRuntimeStopGameplay();
            return;
        }
        if (num == DDR_LM_RUNTIME_START)
        {
            ddrRuntimeStartFromPayload(str);
            return;
        }
        if (num == DDR_LM_CHART_READY)
        {
            ddrRuntimeHandleChartReady(str);
            return;
        }
        if (num == DDR_LM_CHART_FAIL)
        {
            if (gRuntimeLoading)
            {
                ddrRuntimeFail(str);
            }
            return;
        }
        if (num == DDR_LM_RUNTIME_CONTROL)
        {
            list tokens = llParseStringKeepNulls(str, ["|"], []);
            integer held = (integer)llList2String(tokens, 0);
            integer changedMask = (integer)llList2String(tokens, 1);
            ddrRuntimeHandleControl(held, changedMask);
            return;
        }
        if (num == DDR_LM_RUNTIME_RESCAN_LINKS)
        {
            // Renderer rescan is handled by sldr_game_renderer.lsl.
            return;
        }
        if (num == DDR_LM_RUNTIME_DEBUG)
        {
            string value = llToLower(llStringTrim(str, STRING_TRIM));
            if (value == "1" || value == "on" || value == "true")
            {
                ddrDebugSet(TRUE);
            }
            else
            {
                ddrDebugSet(FALSE);
            }
            return;
        }
        if (num == DDR_LM_RUNTIME_STATUS)
        {
            ddrRuntimeSendStatus();
            return;
        }
    }

    timer()
    {
        ddrRuntimeTick();
    }
}
