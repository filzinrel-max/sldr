//mono
#include "../include/ddr_constants.lslh"
#include "../include/ddr_config_engine.lslh"
#include "../include/ddr_debug_engine.lslh"
#include "../include/ddr_link_messages.lslh"

#include "ddr_chart_data_loader.lslh"

integer gChartLoading = FALSE;
integer gChartLoadStage = 0; // 0=idle,1=index,2=chunks
key gChartRequestId = NULL_KEY;

string gChartIndexUrl = "";
string gChartBaseUrl = "";
list gChartChunkUrls = [];
integer gChartChunkCursor = 0;

integer ddrChartLoaderSend(integer code, string payload)
{
    llMessageLinked(LINK_SET, code, payload, NULL_KEY);
    return TRUE;
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

integer ddrChartLoaderStopAndReset()
{
    gChartLoading = FALSE;
    gChartLoadStage = 0;
    gChartRequestId = NULL_KEY;
    gChartIndexUrl = "";
    gChartBaseUrl = "";
    gChartChunkUrls = [];
    gChartChunkCursor = 0;
    ddrChartReset();
    return TRUE;
}

integer ddrChartRequestUrl(string url)
{
    gChartRequestId = llHTTPRequest(
        url,
        [
            HTTP_METHOD, "GET",
            HTTP_MIMETYPE, "text/plain"
        ],
        ""
    );
    if (gChartRequestId == NULL_KEY)
    {
        return FALSE;
    }
    return TRUE;
}

integer ddrChartLoaderStart(string chartIndexUrl)
{
    if (chartIndexUrl == "")
    {
        ddrChartLoaderSend(DDR_LM_CHART_FAIL, "missing-chart-url");
        return FALSE;
    }

    gChartLoading = TRUE;
    gChartLoadStage = 1;
    gChartIndexUrl = chartIndexUrl;
    gChartBaseUrl = ddrUrlDirectory(chartIndexUrl);
    gChartChunkUrls = [];
    gChartChunkCursor = 0;

    if (!ddrChartRequestUrl(gChartIndexUrl))
    {
        gChartLoading = FALSE;
        ddrChartLoaderSend(DDR_LM_CHART_FAIL, "chart-request-failed");
        return FALSE;
    }
    return TRUE;
}

integer ddrChartLoaderSendReady()
{
    string payload = "{}";
    payload = llJsonSetValue(payload, ["seq"], (string)gChartStoreSeq);
    payload = llJsonSetValue(payload, ["difficulty"], gChartDifficultyName);
    payload = llJsonSetValue(payload, ["meter"], (string)gChartMeter);
    payload = llJsonSetValue(payload, ["duration"], (string)gChartDurationSeconds);
    payload = llJsonSetValue(payload, ["notes"], (string)gChartTotalNotes);
    payload = llJsonSetValue(payload, ["holds"], (string)gChartTotalHolds);
    ddrChartLoaderSend(DDR_LM_CHART_READY, payload);
    return TRUE;
}

integer ddrChartBuildChunkUrlList(string chunksJson)
{
    gChartChunkUrls = [];
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
            gChartChunkUrls += [ddrJoinUrl(gChartBaseUrl, item)];
        }
    }
    return llGetListLength(gChartChunkUrls) > 0;
}

integer ddrParseIndexAndStartChunks(string body)
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

    string difficulty = llJsonGetValue(body, ["d"]);
    if (difficulty == JSON_INVALID)
    {
        difficulty = "";
    }

    integer meter = 0;
    string meterRaw = llJsonGetValue(body, ["m"]);
    if (meterRaw != JSON_INVALID)
    {
        meter = (integer)meterRaw;
    }

    float duration = 0.0;
    string durationRaw = llJsonGetValue(body, ["du"]);
    if (durationRaw != JSON_INVALID)
    {
        duration = (float)durationRaw;
    }

    string chunks = llJsonGetValue(body, ["c"]);
    if (!ddrChartBuildChunkUrlList(chunks))
    {
        return FALSE;
    }

    ddrChartBeginBuild(difficulty, meter, duration);
    gChartChunkCursor = 0;
    gChartLoadStage = 2;
    return ddrChartRequestUrl(llList2String(gChartChunkUrls, gChartChunkCursor));
}

integer ddrChartFindSeparator(string text, integer fromIndex)
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

integer ddrChartParseChunkRows(string chunkBody)
{
    if (chunkBody == "")
    {
        return TRUE;
    }

    integer len = llStringLength(chunkBody);
    integer cursor = 0;
    while (cursor < len)
    {
        integer sepPos = ddrChartFindSeparator(chunkBody, cursor);
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

integer ddrChartHandleNextChunk()
{
    if (gChartChunkCursor + 1 >= llGetListLength(gChartChunkUrls))
    {
        if (!ddrChartFinalizeBuild())
        {
            ddrChartLoaderSend(DDR_LM_CHART_FAIL, "chart-empty");
            return FALSE;
        }

        gChartLoading = FALSE;
        gChartLoadStage = 0;
        gChartRequestId = NULL_KEY;
        gChartChunkUrls = [];
        gChartChunkCursor = 0;
        ddrChartLoaderSendReady();
        return TRUE;
    }

    gChartChunkCursor = gChartChunkCursor + 1;
    return ddrChartRequestUrl(llList2String(gChartChunkUrls, gChartChunkCursor));
}

default
{
    state_entry()
    {
        llSetMemoryLimit(65536);
        ddrChartLoaderStopAndReset();
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
    }

    link_message(integer senderNum, integer num, string str, key id)
    {
        if (num == DDR_LM_RUNTIME_RESET || num == DDR_LM_CHART_CANCEL)
        {
            ddrChartLoaderStopAndReset();
            return;
        }
        if (num == DDR_LM_CHART_LOAD)
        {
            ddrChartLoaderStopAndReset();
            ddrChartLoaderStart(str);
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
        if (requestId != gChartRequestId)
        {
            return;
        }

        gChartRequestId = NULL_KEY;
        if (!gChartLoading)
        {
            return;
        }

        if (status < 200 || status >= 300)
        {
            ddrChartLoaderSend(DDR_LM_CHART_FAIL, "chart-http-" + (string)status);
            ddrChartLoaderStopAndReset();
            return;
        }

        if (gChartLoadStage == 1)
        {
            if (!ddrParseIndexAndStartChunks(body))
            {
                ddrChartLoaderSend(DDR_LM_CHART_FAIL, "chart-index-parse-failed");
                ddrChartLoaderStopAndReset();
            }
            return;
        }

        if (gChartLoadStage == 2)
        {
            if (!ddrChartParseChunkRows(body))
            {
                ddrChartLoaderSend(DDR_LM_CHART_FAIL, "chart-chunk-parse-failed");
                ddrChartLoaderStopAndReset();
                return;
            }

            if (!ddrChartHandleNextChunk())
            {
                ddrChartLoaderStopAndReset();
            }
            return;
        }

        ddrChartLoaderSend(DDR_LM_CHART_FAIL, "chart-loader-invalid-stage");
        ddrChartLoaderStopAndReset();
    }
}
