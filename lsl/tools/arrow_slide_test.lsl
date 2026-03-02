// Stacked linked-prim arrow test using client-side texture animation.
// - Each selected link is one slot in a stacked lane.
// - Script only spawns/stops arrows; motion is rendered by llSetLinkTextureAnim.
// - This keeps movement smooth on the client.

integer TEST_FACE = ALL_SIDES;
string ARROW_TEXTURE = "";
vector ARROW_TINT = <1.0, 1.0, 1.0>;
float ARROW_ALPHA = 1.0;

// Base texture transform applied before animation starts.
float TEXTURE_REPEAT_X = 1.0;
float TEXTURE_REPEAT_Y = 1.0;
float TEXTURE_ROTATE_DEGREES = 90.0;

// llSet(Link)TextureAnim controls.
// Smooth mode scrolls in texture X; 90-degree rotation commonly maps this to vertical travel.
float ANIM_START = 1.0;
float ANIM_LENGTH = 1.0;
integer ANIM_REVERSE = TRUE; // TRUE usually gives upward travel with the defaults above.

// Timing
float TRAVEL_SECONDS = 1.0;  // one arrow duration
float SPAWN_INTERVAL = 0.10; // 10 slots * 0.10 => up to 10 concurrent arrows
float TICK_SECONDS = 0.05;   // script cadence for spawn/cleanup only

// Link range used as stacked slots
integer START_LINK = 2;
integer END_LINK = 11;

list gLinks = [];         // [linkNum, ...]
list gSlotActive = [];    // [0/1, ...]
list gSlotEndTimes = [];  // [endTimeSeconds, ...]

integer gReady = FALSE;
integer gNextSlot = 0;
float gNextSpawnAt = 0.0;

float gTravelSeconds = 1.0;
float gSpawnInterval = 0.10;
float gTickSeconds = 0.05;
float gAnimRate = 1.0;

integer ddrClampInt(integer value, integer minValue, integer maxValue)
{
    if (value < minValue)
    {
        return minValue;
    }
    if (value > maxValue)
    {
        return maxValue;
    }
    return value;
}

integer ddrSetSlotVisible(integer linkNum, float alpha)
{
    float rot = TEXTURE_ROTATE_DEGREES * DEG_TO_RAD;
    if (ARROW_TEXTURE != "")
    {
        llSetLinkPrimitiveParamsFast(
            linkNum,
            [
                PRIM_TEXTURE, TEST_FACE, ARROW_TEXTURE, <TEXTURE_REPEAT_X, TEXTURE_REPEAT_Y, 0.0>, <0.0, 0.0, 0.0>, rot,
                PRIM_COLOR, TEST_FACE, ARROW_TINT, alpha
            ]
        );
    }
    else
    {
        llSetLinkPrimitiveParamsFast(
            linkNum,
            [
                PRIM_COLOR, TEST_FACE, ARROW_TINT, alpha
            ]
        );
    }
    return TRUE;
}

integer ddrStopSlotAnim(integer linkNum)
{
    llSetLinkTextureAnim(linkNum, 0, TEST_FACE, 0, 0, 0.0, 0.0, 0.0);
    ddrSetSlotVisible(linkNum, 0.0);
    return TRUE;
}

integer ddrStartSlotAnim(integer linkNum)
{
    ddrSetSlotVisible(linkNum, ARROW_ALPHA);
    // Smooth one-shot pan for this slot.
    llSetLinkTextureAnim(linkNum, ANIM_ON | SMOOTH, TEST_FACE, 1, 1, ANIM_START, ANIM_LENGTH, gAnimRate);
    return TRUE;
}

integer ddrHideAllSlots()
{
    integer i = 0;
    integer count = llGetListLength(gLinks);
    for (; i < count; ++i)
    {
        ddrStopSlotAnim(llList2Integer(gLinks, i));
    }
    return TRUE;
}

integer ddrBuildSlots()
{
    gLinks = [];
    gSlotActive = [];
    gSlotEndTimes = [];

    integer primCount = llGetNumberOfPrims();
    integer first = ddrClampInt(START_LINK, 1, primCount);
    integer last = END_LINK;
    if (last <= 0 || last > primCount)
    {
        last = primCount;
    }
    if (first > last)
    {
        integer swapValue = first;
        first = last;
        last = swapValue;
    }

    integer linkNum = first;
    for (; linkNum <= last; ++linkNum)
    {
        gLinks += [linkNum];
        gSlotActive += [FALSE];
        gSlotEndTimes += [0.0];
    }

    gTravelSeconds = TRAVEL_SECONDS;
    if (gTravelSeconds <= 0.0)
    {
        gTravelSeconds = 1.0;
    }
    gSpawnInterval = SPAWN_INTERVAL;
    if (gSpawnInterval <= 0.0)
    {
        gSpawnInterval = 0.10;
    }
    gTickSeconds = TICK_SECONDS;
    if (gTickSeconds <= 0.0)
    {
        gTickSeconds = 0.05;
    }

    gAnimRate = llFabs(ANIM_LENGTH) / gTravelSeconds;
    if (gAnimRate <= 0.0)
    {
        gAnimRate = 1.0 / gTravelSeconds;
    }
    if (ANIM_REVERSE)
    {
        gAnimRate = -gAnimRate;
    }

    gReady = (llGetListLength(gLinks) > 0);
    gNextSlot = 0;
    llResetTime();
    gNextSpawnAt = 0.0;
    ddrHideAllSlots();
    llSetTimerEvent(gTickSeconds);

    llOwnerSay(
        "[ArrowSlideTest] slots=" + (string)llGetListLength(gLinks) +
        " links=" + llDumpList2String(gLinks, ",") +
        " travel=" + (string)gTravelSeconds + "s spawn=" + (string)gSpawnInterval + "s rate=" + (string)gAnimRate
    );
    return gReady;
}

integer ddrSpawnArrow(float nowSeconds)
{
    integer slotCount = llGetListLength(gLinks);
    if (slotCount <= 0)
    {
        return FALSE;
    }

    if (gNextSlot >= slotCount)
    {
        gNextSlot = 0;
    }

    integer slotIndex = gNextSlot;
    integer linkNum = llList2Integer(gLinks, slotIndex);

    gSlotActive = llListReplaceList(gSlotActive, [TRUE], slotIndex, slotIndex);
    gSlotEndTimes = llListReplaceList(gSlotEndTimes, [nowSeconds + gTravelSeconds], slotIndex, slotIndex);
    ddrStartSlotAnim(linkNum);

    ++gNextSlot;
    if (gNextSlot >= slotCount)
    {
        gNextSlot = 0;
    }
    return TRUE;
}

integer ddrCleanupFinished(float nowSeconds)
{
    integer i = 0;
    integer count = llGetListLength(gLinks);
    for (; i < count; ++i)
    {
        if (llList2Integer(gSlotActive, i))
        {
            float endAt = llList2Float(gSlotEndTimes, i);
            if (nowSeconds >= endAt)
            {
                gSlotActive = llListReplaceList(gSlotActive, [FALSE], i, i);
                ddrStopSlotAnim(llList2Integer(gLinks, i));
            }
        }
    }
    return TRUE;
}

integer ddrTick()
{
    if (!gReady)
    {
        return FALSE;
    }

    float nowSeconds = llGetTime();
    while (nowSeconds >= gNextSpawnAt)
    {
        ddrSpawnArrow(nowSeconds);
        gNextSpawnAt += gSpawnInterval;
    }
    ddrCleanupFinished(nowSeconds);
    return TRUE;
}

default
{
    state_entry()
    {
        ddrBuildSlots();
    }

    on_rez(integer startParam)
    {
        llResetScript();
    }

    changed(integer changeMask)
    {
        if (changeMask & CHANGED_LINK)
        {
            ddrBuildSlots();
        }
    }

    touch_start(integer total)
    {
        if (llDetectedKey(0) == llGetOwner())
        {
            ddrBuildSlots();
        }
    }

    timer()
    {
        ddrTick();
    }
}
