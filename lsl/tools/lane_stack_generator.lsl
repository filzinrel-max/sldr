// Lane stack generator tool.
// Put one or more lane template OBJECTS in this prim's inventory, then click.
// For each template object, this script rezzes N copies at the same position,
// links them to this tool, and renames them:
//   {templateName}_01 ... {templateName}_NN
//
// Notes:
// - Generated prims are linked to THIS object (this object stays as root).
// - If you place multiple templates in inventory, each gets its own stack.
// - Stacks are offset by TEMPLATE_GROUP_SPACING so they do not overlap.

integer COPIES_PER_TEMPLATE = 10;
vector STACK_REZ_OFFSET = <0.0, 0.0, 0.8>;
vector TEMPLATE_GROUP_SPACING = <0.8, 0.0, 0.0>;
float WORK_TIMER_SECONDS = 0.20;
integer MAX_RENAME_RETRIES = 30;

list gTemplateNames = []; // [name, ...]
integer gTemplateIndex = 0;
integer gCopyIndex = 1; // 1..COPIES_PER_TEMPLATE

integer gBusy = FALSE;
integer gWaitingForRez = FALSE;
integer gRezzingFinished = FALSE;
string gPendingRename = "";

list gRenameQueue = []; // [key, name, retries, ...]

string ddrPad2(integer value)
{
    if (value < 10)
    {
        return "0" + (string)value;
    }
    return (string)value;
}

string ddrSlotName(string templateName, integer copyIndex)
{
    return templateName + "_" + ddrPad2(copyIndex);
}

integer ddrFindLinkByKey(key objectKey)
{
    integer linkCount = llGetNumberOfPrims();
    integer linkNum = 1;
    for (; linkNum <= linkCount; ++linkNum)
    {
        if (llGetLinkKey(linkNum) == objectKey)
        {
            return linkNum;
        }
    }
    return 0;
}

list ddrCollectTemplates()
{
    list out = [];
    integer invCount = llGetInventoryNumber(INVENTORY_OBJECT);
    integer i = 0;
    for (; i < invCount; ++i)
    {
        string name = llGetInventoryName(INVENTORY_OBJECT, i);
        if (name != "")
        {
            out += [name];
        }
    }
    return out;
}

vector ddrTemplateRezPos(integer templateIndex)
{
    vector rootPos = llGetPos();
    return rootPos + STACK_REZ_OFFSET + (TEMPLATE_GROUP_SPACING * (float)templateIndex);
}

integer ddrQueueRename(key objectKey, string targetName)
{
    gRenameQueue += [objectKey, targetName, 0];
    return TRUE;
}

integer ddrProcessRenameQueue()
{
    list remaining = [];
    integer len = llGetListLength(gRenameQueue);
    integer i = 0;
    for (; i < len; i += 3)
    {
        key objectKey = (key)llList2String(gRenameQueue, i);
        string targetName = llList2String(gRenameQueue, i + 1);
        integer retries = llList2Integer(gRenameQueue, i + 2);

        integer linkNum = ddrFindLinkByKey(objectKey);
        if (linkNum > 0)
        {
            llSetLinkPrimitiveParamsFast(linkNum, [PRIM_NAME, targetName]);
        }
        else
        {
            ++retries;
            if (retries <= MAX_RENAME_RETRIES)
            {
                remaining += [objectKey, targetName, retries];
            }
            else
            {
                llOwnerSay("[LaneGen] Failed to rename after retries: " + targetName);
            }
        }
    }
    gRenameQueue = remaining;
    return TRUE;
}

integer ddrWorkDone()
{
    return gRezzingFinished && !gWaitingForRez && (llGetListLength(gRenameQueue) == 0);
}

integer ddrFinishWork()
{
    ddrProcessRenameQueue();
    gBusy = FALSE;
    gWaitingForRez = FALSE;
    gRezzingFinished = FALSE;
    llSetTimerEvent(0.0);
    llOwnerSay("[LaneGen] Done.");
    return TRUE;
}

integer ddrStartWork()
{
    if (gBusy)
    {
        llOwnerSay("[LaneGen] Already running.");
        return FALSE;
    }

    gTemplateNames = ddrCollectTemplates();
    if (llGetListLength(gTemplateNames) <= 0)
    {
        llOwnerSay("[LaneGen] No OBJECT templates in inventory.");
        return FALSE;
    }

    gTemplateIndex = 0;
    gCopyIndex = 1;
    gBusy = TRUE;
    gWaitingForRez = FALSE;
    gRezzingFinished = FALSE;
    gPendingRename = "";
    gRenameQueue = [];
    llSetTimerEvent(WORK_TIMER_SECONDS);
    llOwnerSay(
        "[LaneGen] Starting. templates=" + (string)llGetListLength(gTemplateNames) +
        " copiesPerTemplate=" + (string)COPIES_PER_TEMPLATE
    );
    return TRUE;
}

integer ddrRezNext()
{
    if (!gBusy || gWaitingForRez || gRezzingFinished)
    {
        return FALSE;
    }

    integer templateCount = llGetListLength(gTemplateNames);
    if (gTemplateIndex >= templateCount)
    {
        gRezzingFinished = TRUE;
        return TRUE;
    }

    string templateName = llList2String(gTemplateNames, gTemplateIndex);
    gPendingRename = ddrSlotName(templateName, gCopyIndex);

    vector rezPos = ddrTemplateRezPos(gTemplateIndex);
    gWaitingForRez = TRUE;
    llRezObject(templateName, rezPos, ZERO_VECTOR, llGetRot(), 0);
    return TRUE;
}

integer ddrAdvanceCopyCursor()
{
    ++gCopyIndex;
    if (gCopyIndex > COPIES_PER_TEMPLATE)
    {
        gCopyIndex = 1;
        ++gTemplateIndex;
    }
    return TRUE;
}

default
{
    state_entry()
    {
        llOwnerSay("[LaneGen] Ready. Put lane OBJECT templates in inventory, then click.");
    }

    on_rez(integer startParam)
    {
        llResetScript();
    }

    touch_start(integer total)
    {
        if (llDetectedKey(0) != llGetOwner())
        {
            return;
        }
        ddrStartWork();
    }

    object_rez(key objectKey)
    {
        if (!gBusy || !gWaitingForRez)
        {
            return;
        }

        llCreateLink(objectKey, FALSE);
        ddrQueueRename(objectKey, gPendingRename);
        ddrAdvanceCopyCursor();
        gWaitingForRez = FALSE;
    }

    timer()
    {
        if (!gBusy)
        {
            llSetTimerEvent(0.0);
            return;
        }

        ddrProcessRenameQueue();
        ddrRezNext();

        if (ddrWorkDone())
        {
            ddrFinishWork();
        }
    }
}

