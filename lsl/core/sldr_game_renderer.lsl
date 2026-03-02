//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config_renderer.lslh"
#include "../include/ddr_debug_engine.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_chart_data_loader_renderer.lslh"
#include "ddr_lane_renderer.lslh"

integer gRenderActive = FALSE;
integer gRenderLoading = FALSE;
key gRenderRequestId = NULL_KEY;

string gRenderChartIndexUrl = "";
string gRenderChartBaseUrl = "";
list gRenderChunkUrls = [];
integer gRenderChunkCursor = 0;
integer gRenderLoadStage = 0; // 0=idle,1=index,2=chunks

integer gRenderSongClockStarted = FALSE;
float gRenderSongClockStartAt = 0.0;

integer ddrRenderClockStart()
{
    gRenderSongClockStartAt = ddrNow() + DDR_PLAY_START_DELAY;
    gRenderSongClockStarted = TRUE;
    return TRUE;
}

integer ddrRenderClockStop()
{
    gRenderSongClockStarted = FALSE;
    return TRUE;
}

float ddrRenderSongTimeNow()
{
    if (!gRenderSongClockStarted)
    {
        return -9999.0;
    }
    return ddrNow() - gRenderSongClockStartAt;
}

integer ddrStartsWith(string text, string prefix)
{
    integer prefixLen = llStringLength(prefix);
    if (llStringLength(text) < prefixLen)
    {
        return FALSE;
    }
    return llGetSubString(text, 0, prefixLen - 1) == prefix;
}

string ddrUrlDirectory(string url)
{
    integer len = llStringLength(url);
    integer i = len - 1;
    for (; i >= 0; --i)
    {
        if (llGetSubString(url, i, i) == "/")
        {
            return llGetSubString(url, 0, i - 1);
        }
    }
    return url;
}

string ddrJoinUrl(string baseUrl, string relativeOrAbsolute)
{
    if (relativeOrAbsolute == "")
    {
        return "";
    }
    if (ddrStartsWith(relativeOrAbsolute, "http://") || ddrStartsWith(relativeOrAbsolute, "https://"))
    {
        return relativeOrAbsolute;
    }
    if (baseUrl == "")
    {
        return relativeOrAbsolute;
    }
    return baseUrl + "/" + relativeOrAbsolute;
}

integer ddrRenderStop()
{
    gRenderActive = FALSE;
    gRenderLoading = FALSE;
    gRenderRequestId = NULL_KEY;
    gRenderChartIndexUrl = "";
    gRenderChartBaseUrl = "";
    gRenderChunkUrls = [];
    gRenderChunkCursor = 0;
    gRenderLoadStage = 0;
    ddrRenderClockStop();
    ddrChartReset();
    if (gRendererInitialized)
    {
        ddrRendererReset();
    }
    return TRUE;
}

integer ddrRenderRequestUrl(string url)
{
    gRenderRequestId = llHTTPRequest(
        url,
        [
            HTTP_METHOD, "GET",
            HTTP_MIMETYPE, "text/plain"
        ],
        ""
    );
    if (gRenderRequestId == NULL_KEY)
    {
        return FALSE;
    }
    return TRUE;
}

integer ddrRenderBuildChunkUrlList(string chunksJson)
{
    gRenderChunkUrls = [];
    if (chunksJson == JSON_INVALID || llJsonValueType(chunksJson, []) != JSON_ARRAY)
    {
        return FALSE;
    }

    list chunkList = llJson2List(chunksJson);
    integer i = 0;
    integer count = llGetListLength(chunkList);
    for (; i < count; ++i)
    {
        string item = llStringTrim(llList2String(chunkList, i), STRING_TRIM);
        if (item != "")
        {
            gRenderChunkUrls += [ddrJoinUrl(gRenderChartBaseUrl, item)];
        }
    }
    return llGetListLength(gRenderChunkUrls) > 0;
}

integer ddrRenderParseIndexAndStartChunks(string body)
{
    if (body == "" || llJsonValueType(body, []) != JSON_OBJECT)
    {
        return FALSE;
    }

    string fmt = llJsonGetValue(body, ["fmt"]);
    if (fmt == JSON_INVALID || fmt != "sldr-chart-chunks-v1")
    {
        return FALSE;
    }

    float duration = 0.0;
    string durationRaw = llJsonGetValue(body, ["du"]);
    if (durationRaw != JSON_INVALID)
    {
        duration = (float)durationRaw;
    }

    string chunks = llJsonGetValue(body, ["c"]);
    if (!ddrRenderBuildChunkUrlList(chunks))
    {
        return FALSE;
    }

    ddrChartBeginBuild(duration);
    gRenderChunkCursor = 0;
    gRenderLoadStage = 2;
    return ddrRenderRequestUrl(llList2String(gRenderChunkUrls, gRenderChunkCursor));
}

integer ddrRenderFindSeparator(string text, integer fromIndex)
{
    integer len = llStringLength(text);
    integer i = fromIndex;
    for (; i < len; ++i)
    {
        if (llGetSubString(text, i, i) == ";")
        {
            return i;
        }
    }
    return -1;
}

integer ddrRenderParseChunkRows(string chunkBody)
{
    if (chunkBody == "")
    {
        return TRUE;
    }

    integer len = llStringLength(chunkBody);
    integer cursor = 0;
    while (cursor < len)
    {
        integer sepPos = ddrRenderFindSeparator(chunkBody, cursor);
        string row = "";
        if (sepPos < 0)
        {
            row = llGetSubString(chunkBody, cursor, -1);
            cursor = len;
        }
        else
        {
            if (sepPos > cursor)
            {
                row = llGetSubString(chunkBody, cursor, sepPos - 1);
            }
            cursor = sepPos + 1;
        }

        row = llStringTrim(row, STRING_TRIM);
        if (row == "")
        {
            jump next_row;
        }

        list fields = llParseStringKeepNulls(row, [","], []);
        if (llGetListLength(fields) < 4)
        {
            return FALSE;
        }

        integer deltaCs = (integer)llList2String(fields, 0);
        integer pressMask = (integer)llList2String(fields, 1);
        integer holdStartMask = (integer)llList2String(fields, 2);
        integer holdEndMask = (integer)llList2String(fields, 3);
        ddrChartAppendDeltaEvent(deltaCs, pressMask, holdStartMask, holdEndMask);
@next_row;
    }
    return TRUE;
}

integer ddrRenderAdvanceChunkLoad()
{
    if (gRenderChunkCursor + 1 >= llGetListLength(gRenderChunkUrls))
    {
        if (!ddrChartFinalizeBuild())
        {
            ddrDebug("RENDER", "chart empty");
            ddrRenderStop();
            return FALSE;
        }

        ddrRendererReset();
        ddrRenderClockStart();
        gRenderLoading = FALSE;
        gRenderActive = TRUE;
        gRenderLoadStage = 0;
        gRenderRequestId = NULL_KEY;
        gRenderChunkUrls = [];
        gRenderChunkCursor = 0;
        return TRUE;
    }

    gRenderChunkCursor = gRenderChunkCursor + 1;
    return ddrRenderRequestUrl(llList2String(gRenderChunkUrls, gRenderChunkCursor));
}

integer ddrRenderStartFromPayload(string payload)
{
    string chartIndexUrl = llJsonGetValue(payload, ["chartUrl"]);
    if (chartIndexUrl == JSON_INVALID || chartIndexUrl == "")
    {
        ddrDebug("RENDER", "missing chart url");
        return FALSE;
    }

    if (!gRendererInitialized)
    {
        ddrRendererInit();
    }
    ddrRenderStop();

    gRenderChartIndexUrl = chartIndexUrl;
    gRenderChartBaseUrl = ddrUrlDirectory(chartIndexUrl);
    gRenderChunkUrls = [];
    gRenderChunkCursor = 0;
    gRenderLoadStage = 1;
    gRenderLoading = TRUE;
    if (!ddrRenderRequestUrl(gRenderChartIndexUrl))
    {
        gRenderLoading = FALSE;
        ddrDebug("RENDER", "chart request failed");
        return FALSE;
    }
    return TRUE;
}

integer ddrRenderTick()
{
    if (!gRenderActive)
    {
        return FALSE;
    }

    float songTime = ddrRenderSongTimeNow();
    if (songTime < -DDR_RENDER_LOOKAHEAD_SECONDS)
    {
        return FALSE;
    }

    ddrRendererTick(songTime);
    if (songTime >= (gChartDurationSeconds + DDR_POST_SONG_GRACE_SECONDS + 1.0))
    {
        ddrRenderStop();
    }
    return TRUE;
}

integer ddrRenderBoot()
{
    gRenderActive = FALSE;
    gRenderLoading = FALSE;
    gRenderRequestId = NULL_KEY;
    gRenderChartIndexUrl = "";
    gRenderChartBaseUrl = "";
    gRenderChunkUrls = [];
    gRenderChunkCursor = 0;
    gRenderLoadStage = 0;
    ddrRenderClockStop();
    ddrChartReset();
    ddrRendererInit();
    llSetTimerEvent(DDR_TICK_SECONDS);
    return TRUE;
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrRenderBoot();
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
            if (gRendererInitialized)
            {
                ddrRendererDiscoverSlots();
            }
        }
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_RUNTIME_RESET)
        {
            ddrRenderStop();
            return;
        }
        if (num == DDR_LM_RUNTIME_START)
        {
            ddrRenderStartFromPayload(str);
            return;
        }
        if (num == DDR_LM_RUNTIME_RESCAN_LINKS)
        {
            if (!gRendererInitialized)
            {
                return;
            }
            ddrRendererDiscoverSlots();
            ddrRendererReset();
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
    }

    http_response(key requestId, integer status, list metadata, string body)
    {
        if (requestId != gRenderRequestId)
        {
            return;
        }

        gRenderRequestId = NULL_KEY;
        if (!gRenderLoading)
        {
            return;
        }

        if (status < 200 || status >= 300)
        {
            gRenderLoading = FALSE;
            ddrDebug("RENDER", "chart http fail " + (string)status);
            ddrRenderStop();
            return;
        }

        if (gRenderLoadStage == 1)
        {
            if (!ddrRenderParseIndexAndStartChunks(body))
            {
                gRenderLoading = FALSE;
                ddrDebug("RENDER", "chart index parse fail");
                ddrRenderStop();
            }
            return;
        }

        if (gRenderLoadStage == 2)
        {
            if (!ddrRenderParseChunkRows(body))
            {
                gRenderLoading = FALSE;
                ddrDebug("RENDER", "chart chunk parse fail");
                ddrRenderStop();
                return;
            }

            if (!ddrRenderAdvanceChunkLoad())
            {
                gRenderLoading = FALSE;
                ddrDebug("RENDER", "chart chunk request fail");
                ddrRenderStop();
            }
            return;
        }

        gRenderLoading = FALSE;
        ddrDebug("RENDER", "chart invalid stage");
        ddrRenderStop();
    }

    timer()
    {
        ddrRenderTick();
    }
}
