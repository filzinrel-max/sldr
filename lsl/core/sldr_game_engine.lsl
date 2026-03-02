//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config.lslh"
#include "../include/ddr_debug.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_chart_data_loader.lslh"
#include "ddr_combo_feedback.lslh"
#include "ddr_scoring.lslh"
#include "ddr_judge_feedback.lslh"
#include "ddr_judgement.lslh"

integer gRuntimeActive = FALSE;
integer gRuntimeLoading = FALSE;
key gRuntimeChartRequestId = NULL_KEY;
integer gRuntimeSystemsReady = FALSE;

string gRuntimeChartUrl = "";

string gRuntimeSongId = "";
string gRuntimeSongTitle = "";
string gRuntimeSongArtist = "";
string gRuntimeSongDifficulty = "";

integer gRuntimeSongClockStarted = FALSE;
float gRuntimeSongClockStartAt = 0.0;

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

integer ddrRuntimeEnsureSystemsReady()
{
    if (gRuntimeSystemsReady)
    {
        return TRUE;
    }

    ddrComboFeedbackInit();
    ddrJudgeFeedbackInit();
    gRuntimeSystemsReady = TRUE;
    ddrDebug("RUNTIME", "systems ready; free memory=" + (string)llGetFreeMemory());
    return TRUE;
}

integer ddrRuntimeStopGameplay()
{
    gRuntimeActive = FALSE;
    gRuntimeLoading = FALSE;
    gRuntimeChartRequestId = NULL_KEY;

    ddrRuntimeClockStop();
    ddrChartReset();
    ddrScoreReset();
    if (gRuntimeSystemsReady)
    {
        ddrComboFeedbackHide();
        ddrJudgeFeedbackHide();
    }
    gPendingNotes = 0;
    gPendingHolds = 0;
    gLaneDown = [FALSE, FALSE, FALSE, FALSE];
    return TRUE;
}

integer ddrRuntimeFail(string reason)
{
    ddrRuntimeStopGameplay();
    ddrRuntimeSend(DDR_LM_MAIN_FAIL, reason);
    return TRUE;
}

integer ddrRuntimeRequestChart()
{
    if (gRuntimeChartUrl == "")
    {
        return FALSE;
    }
    gRuntimeChartRequestId = llHTTPRequest(
        gRuntimeChartUrl,
        [
            HTTP_METHOD, "GET",
            HTTP_MIMETYPE, "text/plain"
        ],
        ""
    );
    if (gRuntimeChartRequestId == NULL_KEY)
    {
        return FALSE;
    }
    ddrDebug("RUNTIME", "chart -> " + gRuntimeChartUrl + " (" + (string)gRuntimeChartRequestId + ")");
    return TRUE;
}

integer ddrRuntimeStartFromPayload(string payload)
{
    string chartUrl = llJsonGetValue(payload, ["chartUrl"]);
    if (chartUrl == JSON_INVALID || chartUrl == "")
    {
        return ddrRuntimeFail("missing-chart-url");
    }

    ddrRuntimeEnsureSystemsReady();
    ddrRuntimeStopGameplay();

    gRuntimeChartUrl = chartUrl;

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

    gRuntimeLoading = TRUE;
    if (!ddrRuntimeRequestChart())
    {
        return ddrRuntimeFail("chart-request-failed");
    }
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
    string payload = ddrScorePayloadJson(
        gRuntimeSongId,
        gRuntimeSongTitle,
        gRuntimeSongArtist,
        gRuntimeSongDifficulty
    );
    ddrRuntimeStopGameplay();
    return ddrRuntimeSend(DDR_LM_MAIN_COMPLETE, payload);
}

integer ddrRuntimeTick()
{
    if (!gRuntimeActive)
    {
        ddrComboFeedbackTick();
        ddrJudgeFeedbackTick();
        return FALSE;
    }

    float songTime = ddrRuntimeSongTimeNow();
    if (songTime < -DDR_RENDER_LOOKAHEAD_SECONDS)
    {
        ddrComboFeedbackTick();
        ddrJudgeFeedbackTick();
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

    ddrComboFeedbackTick();
    ddrJudgeFeedbackTick();
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

integer ddrRuntimeBoot()
{
    gRuntimeSystemsReady = FALSE;
    gRuntimeActive = FALSE;
    gRuntimeLoading = FALSE;
    gRuntimeChartRequestId = NULL_KEY;
    ddrRuntimeClockStop();
    ddrChartReset();
    ddrScoreReset();
    gPendingNotes = 0;
    gPendingHolds = 0;
    gLaneDown = [FALSE, FALSE, FALSE, FALSE];
    llSetTimerEvent(DDR_TICK_SECONDS);
    ddrDebug("RUNTIME", "booted (deferred init); free memory=" + (string)llGetFreeMemory());
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
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

    http_response(key requestId, integer status, list metadata, string body)
    {
        if (requestId != gRuntimeChartRequestId)
        {
            return;
        }

        gRuntimeChartRequestId = NULL_KEY;
        if (!gRuntimeLoading)
        {
            return;
        }

        if (status < 200 || status >= 300)
        {
            ddrRuntimeFail("chart-http-" + (string)status);
            return;
        }
        if (!ddrChartLoadFromCompactJson(body))
        {
            ddrRuntimeFail("chart-parse-failed");
            return;
        }

        gRuntimeSongDifficulty = gChartDifficultyName;

        ddrScoreReset();
        ddrScorePrepareForChart();
        ddrJudgeResetForChart();
        ddrComboFeedbackHide();
        ddrJudgeFeedbackHide();
        ddrRuntimeClockStart();

        gRuntimeLoading = FALSE;
        gRuntimeActive = TRUE;
        ddrRuntimeSendReady();
    }

    timer()
    {
        ddrRuntimeTick();
    }
}
