// =========================================================================
// ClaudePanel - the whole token picture, from Claude Code's own transcripts
// =========================================================================
//
// Opened by ClaudeButton, which carries no numbers itself. Everything here is
// computed by bin/claude-usage.py from ~/.claude/projects/**/*.jsonl.
//
// THE HEADLINE IS THE BLOCK, not the day or the week, because the block is the
// only one of the three that behaves like a budget: it fills, it empties, and
// it resets at a time this panel can name. A daily total is a fact about the
// past; "2h 50m left in this window" is a fact about what happens next.
//
// BILLED AND CACHE READS ARE SHOWN SEPARATELY AND THE PANEL SAYS WHY. They
// differ by two orders of magnitude - 915k against 282M in the block this was
// written during - so adding them produces a number that is almost entirely
// cache traffic and reads as alarming for no reason. Billed is
// input + output + cache writes.
//
// NO PERCENTAGES AND NO PROGRESS BARS AGAINST A LIMIT. The transcripts say
// what was spent and never what the allowance was, so there is no denominator
// on this machine. The sparkline compares blocks against each other, which is
// a comparison the data actually supports.

import Quickshell
import QtQuick

DropPanel {
    id: root
    layerNamespace: "quickshell-claude"
    panelWidth: 360

    function tint(c, a): color { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property int peak: {
        let m = 1
        for (const v of (ClaudeUsage.recent || [])) if (v > m) m = v
        return m
    }

    Column {
        id: stack
        width: parent.width
        spacing: 12

        // --- the block ----------------------------------------------------
        Rectangle {
            width: parent.width
            height: block.implicitHeight + 24
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline

            Column {
                id: block
                anchors { left: parent.left; right: parent.right; leftMargin: 16
                          rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 5

                Text {
                    font.family: Theme.font
                    text: "THIS " + ClaudeUsage.blockHours + "-HOUR BLOCK"
                    color: root.tint(Theme.dim, 0.95)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.weightSemi
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                }

                // THE BIG NUMBER STAYS IN NORMAL FLOW AND THE WORD ALIGNS TO
                // IT, not the other way round. Anchoring the number's baseline
                // to its neighbour took it out of the Row's layout, so the Row
                // sized itself to the 13px word while the 27px number overflowed
                // upward - straight through the heading above it. An anchored
                // child contributes nothing to implicit height, and the only
                // visible symptom is two pieces of text on top of each other.
                Row {
                    spacing: 8
                    Text {
                        id: bigNumber
                        font.family: Theme.font
                        text: ClaudeUsage.ready
                              ? ClaudeUsage.human(ClaudeUsage.blockBilled) : "—"
                        color: Theme.fg
                        font.pixelSize: Theme.fontSizeDisplay
                        // SEMIBOLD, NOT LIGHT. A light 27px number is elegant in
                        // a card that has nothing else in it; this one sits above
                        // three more cards of figures and was the quietest thing
                        // on a panel it is supposed to lead.
                        font.weight: Theme.weightSemi
                        font.letterSpacing: Theme.trackingTight
                    }
                    Text {
                        font.family: Theme.font
                        anchors.baseline: bigNumber.baseline
                        text: "billed"
                        color: Theme.dim
                        font.pixelSize: Theme.fontSize
                    }
                }

                Text {
                    font.family: Theme.font
                    text: ClaudeUsage.ready
                          ? ClaudeUsage.blockMessages
                            + (ClaudeUsage.blockMessages === 1 ? " message" : " messages")
                            + " · resets in "
                            + ClaudeUsage.remaining()
                          : "reading the transcripts"
                    color: Theme.dim
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // --- the shape over time ------------------------------------------
        //
        // Twelve blocks, oldest first, each bar against the tallest of them.
        // Empty blocks are drawn as empty rather than skipped, so a quiet
        // stretch looks like one instead of being compressed out of the chart.
        Rectangle {
            width: parent.width
            height: 84
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline
            visible: (ClaudeUsage.recent || []).length > 0

            Text {
                font.family: Theme.font
                anchors { top: parent.top; left: parent.left; topMargin: 10; leftMargin: 16 }
                text: "LAST " + (ClaudeUsage.recent || []).length + " BLOCKS"
                color: root.tint(Theme.dim, 0.95)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.weightSemi
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8
            }

            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                          leftMargin: 16; rightMargin: 16; bottomMargin: 12 }
                height: 38
                spacing: 4

                Repeater {
                    model: ClaudeUsage.recent || []
                    Item {
                        required property var modelData
                        required property int index
                        width: (parent.width - 4 * ((ClaudeUsage.recent || []).length - 1))
                               / Math.max(1, (ClaudeUsage.recent || []).length)
                        height: parent.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            // A floor of 2px so an empty block is still a mark
                            // on the chart rather than a gap in it.
                            height: Math.max(2, parent.height * (parent.modelData / root.peak))
                            radius: 3
                            // The current block is the live one and takes the
                            // accent; the rest are history and do not.
                            color: parent.index === (ClaudeUsage.recent || []).length - 1
                                   ? Theme.accent : root.tint(Theme.fg, 0.22)
                            Behavior on height { NumberAnimation { duration: Theme.animNormal } }
                        }
                    }
                }
            }
        }

        // --- the totals ---------------------------------------------------
        Rectangle {
            width: parent.width
            height: totals.implicitHeight + 24
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline

            Column {
                id: totals
                anchors { left: parent.left; right: parent.right; leftMargin: 16
                          rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 7

                Repeater {
                    model: [
                        { k: "Today",     v: ClaudeUsage.human(ClaudeUsage.todayBilled),
                          // SINGULAR AT ONE, and one is not a rare case here:
                          // it is what the panel says for the first message of
                          // a block or a day, which is exactly when someone
                          // opens it to check the count is moving.
                          d: ClaudeUsage.todayMessages
                             + (ClaudeUsage.todayMessages === 1 ? " message" : " messages") },
                        { k: "Last 7 days", v: ClaudeUsage.human(ClaudeUsage.weekBilled), d: "" },
                        { k: "Cache reads, this block",
                          v: ClaudeUsage.human(ClaudeUsage.blockCacheRead),
                          d: "not billed as input" }
                    ]
                    Item {
                        required property var modelData
                        width: totals.width
                        height: 20
                        Text {
                            font.family: Theme.font
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: parent.modelData.k
                            color: Theme.fg
                            font.pixelSize: Theme.fontSize
                            font.weight: Theme.weightMedium
                        }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 7
                            Text {
                                font.family: Theme.font
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.d
                                color: root.tint(Theme.dim, 0.7)
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Text {
                                font.family: Theme.font
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.v
                                color: Theme.fg
                                font.pixelSize: Theme.fontSize
                                font.weight: Theme.weightBold
                            }
                        }
                    }
                }
            }
        }

        // --- which models ---------------------------------------------------
        Rectangle {
            width: parent.width
            height: byModel.implicitHeight + 24
            radius: 12
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline
            visible: (ClaudeUsage.models || []).length > 0

            Column {
                id: byModel
                anchors { left: parent.left; right: parent.right; leftMargin: 16
                          rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 7

                Text {
                    font.family: Theme.font
                    text: "BY MODEL, ALL TIME"
                    color: root.tint(Theme.dim, 0.95)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.weightSemi
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                }

                Repeater {
                    model: ClaudeUsage.models || []
                    Item {
                        required property var modelData
                        width: byModel.width
                        height: 18
                        Text {
                            font.family: Theme.font
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: parent.width - 80
                            elide: Text.ElideRight
                            text: parent.modelData.name
                            color: Theme.dim
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        Text {
                            font.family: Theme.font
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: ClaudeUsage.human(parent.modelData.billed)
                            color: Theme.fg
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.weightSemi
                        }
                    }
                }
            }
        }

        // The one thing this panel cannot tell you, said once rather than
        // implied by its absence.
        Text {
            font.family: Theme.font
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Counted from the local transcripts. They record what was "
                  + "spent, never the allowance - so there is no percentage here."
            color: root.tint(Theme.dim, 0.75)
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
