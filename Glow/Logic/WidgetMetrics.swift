import CoreGraphics
import WidgetKit

/// The large widget's layout, in the design file's own numbers.
///
/// Lives in `Glow/Logic` rather than in the widget target because the app needs
/// one number out of it: how many rows the widget can show. The grid marks that
/// boundary, and a second copy of the figure in the app would be a copy that
/// could drift.
///
/// Node `83:1676` is authored at 1x — 338 × 354 — so these are read straight
/// off it rather than halved from a 2x frame or measured off a render. That is
/// the design's frame, not a universal claim about a phone (#544).
///
/// Every value here is a *design* number. Nothing is derived from a screenshot
/// and nothing is rounded to something tidier; where the file is on a half point
/// this is too, because half a point is a real pixel at 2x and two of them at 3x.
enum WidgetMetrics {
    /// The large widget's authored reference size. The design file is exactly
    /// this at 1x; WidgetKit's live size belongs to `WidgetDisplaySize`.
    static let largeWidth: CGFloat = 338
    static let largeHeight: CGFloat = 354

    /// The small widget's authored reference size. Square, and the width the
    /// medium and large design frames share is two of these plus the gap.
    static let smallSide: CGFloat = 158

    /// The stable frame the design gives each family.
    ///
    /// Two readers deliberately remain: the render harness renders every
    /// family in this stable design coordinate system, and
    /// `largeRowCapacity` is the same numbers by another name. The Widgets tab
    /// no longer treats these as device truth: `WidgetDisplaySize` supplies
    /// WidgetKit's last exact frame on that device and uses this only until
    /// WidgetKit has rendered the family (#544).
    ///
    /// Sizes do vary by device; this is the phone the design is authored
    /// against, not a prediction made from the screen it is running on.
    ///
    /// **No phone measured gives these numbers** (#367). WidgetKit names the
    /// frame it renders into in the archive path it hands the extension, and
    /// three devices name three different ones — read out of Glow's own
    /// `snapshot-cache` and confirmed by pixel-counting a placed widget at 3x
    /// on two of them:
    ///
    /// | device | medium | large |
    /// | --- | --- | --- |
    /// | iPhone 15 Pro | 344.67 × 162.67 | 344.67 × 360.00 |
    /// | iPhone 17 Pro | 349.67 × 164.33 | 349.67 × 365.00 |
    /// | iPhone 17e | 342.00 × 162.00 | 342.00 × 358.00 |
    ///
    /// **For the large family that gap cost a row**, which is #410 and the
    /// `rowLayout` above. **For the medium family it costs nothing**, and the
    /// reason is slack rather than luck: ten rows fill the design's large frame
    /// exactly, while four rows fill 120 of a medium's 134pt of content. The
    /// division that counts them lands at 4.4375 on the design frame and at
    /// 4.45–4.50 on all three phones, so the design frame is the *tightest*
    /// medium fit of the four rather than the one the fit held on — the mirror
    /// image of the large family. `WidgetMetricsTests` pins that ordering.
    ///
    /// Replacing these numbers with one phone's would pin a phone rather than
    /// pin none and move both committed render baselines. The environmental
    /// frame therefore lives separately in `WidgetDisplaySize` (#544).
    static func size(of family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: CGSize(width: largeWidth, height: smallSide)
        case .systemLarge: CGSize(width: largeWidth, height: largeHeight)
        // Small, and anything this app does not ship — a square is the least
        // wrong answer, and `WidgetKind.families` is what keeps the question
        // from being asked.
        default: CGSize(width: smallSide, height: smallSide)
        }
    }

    /// How many widgets of this family sit side by side on a Home Screen.
    ///
    /// Derived from the sizes above rather than written down, for the reason
    /// everything in this type is: two Small widgets occupy one Medium's
    /// footprint because `smallSide` fits twice into `largeWidth`, and if
    /// either number ever moves this answer moves with it. The Widgets tab
    /// lays its previews out on this (#274).
    static func perRow(_ family: WidgetFamily) -> Int {
        let width = size(of: family).width
        guard width > 0 else { return 1 }
        return max(1, Int(largeWidth / width))
    }

    /// How many rows the design's own frame holds, for a family.
    ///
    /// **This is where "the design's row count" is declared** (#410), and it is
    /// declared as a *derivation from the design frame* rather than as a
    /// literal. The frame is already written down here — 338 × 354 read off
    /// node `83:1676` — and the row count is nothing more than what that frame
    /// holds at the design's own slot, gap and insets. A literal `10` beside it
    /// would be a second spelling of a number this file can already compute,
    /// and every constant in this type that was ever written down twice has
    /// drifted at least once.
    ///
    /// What is new is that the answer is now *used at runtime*, not only
    /// reported: `rowLayout` shrinks a real frame's slot until this many rows
    /// fit it. So the design specifies a row count and the frame supplies a
    /// size, which is the direction that reads right — a phone that is 3%
    /// wider than the design file is not a phone that shows fewer habits.
    ///
    /// `hasHeader` is the view's call — only the large family spends a row on
    /// the weekday letters — so it is asked for rather than re-decided here.
    static func designRowCount(_ family: WidgetFamily, hasHeader: Bool) -> Int {
        let frame = size(of: family)
        let track = frame.width
            - padLeading(for: family) - padTrailing(for: family)
            - labelWidth - labelGap
        return rowCapacity(
            height: frame.height - padTop - padBottom,
            slot: SlotLayout.slotHeight(trackWidth: track),
            hasHeader: hasHeader
        )
    }

    /// How many rows a large widget shows.
    ///
    /// Ten since #331, and derived rather than written down — every input to it
    /// has moved at least once. The app reads this to mark where its grid stops
    /// being visible on the home screen.
    ///
    /// **It is true on every frame since #410, and was true only on the design
    /// frame before it.** The number itself has not moved; what moved is the
    /// widget under it. Ten rows fit `338 × 354` with zero slack, and every
    /// phone measured is proportionally *wider* than that, so the row block
    /// outgrew the height by half a point to two points and the widget drew
    /// nine — while this constant went on saying ten to the app's boundary
    /// hairline and to `WidgetRowLimit.large`. `rowLayout` is what makes the
    /// promise good: the slot gives way to the height, so `designRowCount` rows
    /// are drawn on any frame in this neighbourhood rather than on one.
    static var largeRowCapacity: Int {
        designRowCount(.systemLarge, hasHeader: true)
    }

    /// The row block for a frame the system actually handed the widget: the
    /// slot every row is drawn at, and how many rows fit at it.
    struct RowLayout {
        /// A row's height — and a daily mark's width, because the two are one
        /// number. The track the marks divide is `SlotLayout.trackWidth(
        /// dailySlot:)` of this, which is at most the track the frame offers.
        let slot: CGFloat
        /// How many rows to draw. Never below the design's own count, because
        /// the slot was chosen to make that many fit.
        let capacity: Int
    }

    /// The slot and the capacity for a real frame, as one answer (#410).
    ///
    /// **The two used to be derived apart, and that is what lost a row.**
    /// `SlotLayout.slotHeight` answers from the track alone — a row is as tall
    /// as a daily mark is wide — so a row block's height grows with the frame's
    /// *width* while the space for it grows with the frame's *height*. On the
    /// design frame those balance to the point: ten rows are 312 of 312, which
    /// `WidgetMetricsTests.largeCapacityHasNoSlack` pins deliberately. Every
    /// phone measured is proportionally wider than the design frame, so ten
    /// rows overran the height by 0.44pt (iPhone 17e) to 1.97pt (17 Pro) out of
    /// ~320, the floor division took nine, and a habit was silently missing
    /// from every large widget on every device. `rowsOffset` then split the
    /// leftover, which is why the grid also read as floating — a consequence of
    /// the lost row rather than a second fault.
    ///
    /// So the height gets a say. The slot is the smaller of the track's answer
    /// and the largest slot at which `designRows` rows still fill the height
    /// exactly: 24.60 rather than 24.74 on an iPhone 15 Pro, 25.10 rather than
    /// 25.30 on a 17 Pro, 24.40 rather than 24.44 on a 17e — 0.2% to 0.8%
    /// smaller. Ten rows are drawn, the block fills the height exactly so
    /// `rowsOffset` is zero, and the bottom margin is `padBottom` on the point.
    ///
    /// **What it costs is the track.** The marks keep their proportion — round
    /// is the one thing a mark cannot give up — so the narrower slot brings a
    /// narrower column rhythm with it, and 0.40pt (17e) to 1.77pt (17 Pro) of
    /// the frame's track is left unused at the trailing edge. The right margin
    /// stops being exactly `padTrailing` on a real phone. Of the three things
    /// that cannot all hold on a frame whose aspect differs from the design's —
    /// round marks, a track filled exactly, a height filled exactly — this
    /// gives up the one the design file does not specify.
    ///
    /// The capacity is `max`'d with `designRows` rather than trusted from the
    /// division: a slot chosen to fit exactly divides to a whole number in real
    /// arithmetic and can land a hair under it in floating point, and this row
    /// is the row the issue is about. Where the frame is proportionally *taller*
    /// than the design the cap does not bind, the division is the only answer,
    /// and it is the one that is used.
    static func rowLayout(
        trackWidth: CGFloat, contentHeight: CGFloat, designRows: Int, hasHeader: Bool
    ) -> RowLayout {
        let fromTrack = SlotLayout.slotHeight(trackWidth: trackWidth)
        let available = contentHeight - (hasHeader ? headerHeight + headerGap : 0)
        let fromHeight = designRows > 0
            ? (available - CGFloat(designRows - 1) * rowGap) / CGFloat(designRows)
            : 0
        // Three ways the height has nothing to say, all answered the way this
        // did before #410 — the track's slot, and whatever capacity that
        // yields. A frame proportionally *taller* than the design's is the
        // ordinary one: the rows already fit, so capping would shrink them for
        // nothing. The other two are degenerate — no rows asked for, or a
        // frame too small to hold them at any positive slot, which is what a
        // `GeometryReader` reporting zero on its first pass looks like.
        guard fromHeight > 0, fromHeight < fromTrack else {
            return RowLayout(
                slot: fromTrack,
                capacity: rowCapacity(
                    height: contentHeight, slot: fromTrack, hasHeader: hasHeader
                )
            )
        }
        return RowLayout(
            slot: fromHeight,
            capacity: max(designRows, rowCapacity(
                height: contentHeight, slot: fromHeight, hasHeader: hasHeader
            ))
        )
    }

    /// Content inset. **Asymmetric on both axes, and that is deliberate**
    /// (#331, `docs/week-marks.md` §8.1).
    ///
    /// Left 6, right 14, top 10, bottom 14. Neither axis is centred and none of
    /// the four sits on the 8/4 spacing the rest of the frame uses, so they are
    /// an optical adjustment rather than a derivation — recorded as such here
    /// so the next reader regularises them on purpose or not at all.
    ///
    /// They also do arithmetic. The track is what is left of the width:
    /// `338 − 6 − 14 − 98 − 4 = 216`, which is exactly seven 24pt columns and
    /// six 8pt gaps. And the top pair places the grid's first row: `10 + 14 + 4`
    /// puts it at y=28, where §8.2 measures it.
    static let padLeading: CGFloat = 6
    static let padTrailing: CGFloat = 14
    /// Top and bottom, which used to be one symmetric `padVertical`.
    ///
    /// **#57's point is spent and its reasoning is retired.** `padVertical` was
    /// 15 rather than the file's 16 because that one point bought the medium
    /// family its fifth row — 126pt of content against a 27.45pt pitch is 4.95
    /// rows and the hard cut takes the floor. That whole calculation was
    /// against a 17.455pt slot. The slot is 24 now, and no single point is
    /// within reach of a row boundary at that size: medium holds four rows and
    /// would hold four at any inset in this neighbourhood. So these are the
    /// design's numbers, with nothing borrowed.
    /// The small family's own inset, symmetric where the others are not.
    ///
    /// The week widget's 6/14 is an optical adjustment for a row that starts
    /// with a label column and ends with a mark — it is left-heavy because its
    /// content is. The month has no label column: it is a centred block of
    /// cells, so it is inset evenly. Node `341:3695` puts the grid at x=11 in
    /// a 158pt frame, 11 either side, for a 136pt track (#553). It was 14/14
    /// off node `234:11216`, a 130pt track, until 2026-09-05.
    ///
    /// Applying the week's 6/14 here shifted the whole grid 8pt left and gave
    /// it 138pt of track where the file drew 130 — a width the file has since
    /// moved toward, but symmetric, which the week's pair is not.
    static let smallPad: CGFloat = 11

    /// The leading inset for a family. Small is symmetric; the rest are not.
    static func padLeading(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? smallPad : padLeading
    }

    /// The trailing inset for a family. The two answers agreed at 14 until
    /// #553 and were still asked rather than assumed: the week's 14 is the
    /// optical pair to its 6, and the month's is half a symmetric inset. That
    /// they agreed was coincidence, not derivation, which is why one could
    /// move without the other.
    static func padTrailing(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? smallPad : padTrailing
    }

    static let padTop: CGFloat = 10
    static let padBottom: CGFloat = 14

    /// Header to the first row, and row to row.
    ///
    /// Both 8/4 numbers now (#331): the row gap matches the column gap, so the
    /// grid's pitch is 32 in both directions and a row is as tall as a column
    /// is wide.
    ///
    /// **`rowGap` was never a spacing number, and the reason has just gone.**
    /// It was set by how far a halo spilled out of a row — closing it would
    /// have put each row's light into its neighbour — and it moved from 10 to 8
    /// because the whole grid rescaled, not because it was slack to be taken.
    /// The halo is gone (#394) and nothing spills any more, so the constraint
    /// that fixed this number no longer exists. It is left where it is on
    /// purpose: 8 also matches the column gap and gives the grid a pitch of 32
    /// in both directions (#331), and changing it is a spacing decision to make
    /// deliberately rather than a consequence to take here.
    static let headerGap: CGFloat = 4
    static let rowGap: CGFloat = 8

    /// The label column, and its distance to the track.
    ///
    /// The gap was 15 and is 4 (#331). `nameMaxWidth` below is derived from it
    /// and moves with it — which is the point of the derivation, because left
    /// at its old value a full-length habit name would run 11pt underneath the
    /// first column of marks.
    static let labelWidth: CGFloat = 98
    static let labelGap: CGFloat = 4

    /// Inside the label: the icon's column, and where the name starts.
    ///
    /// The gap is half the former 4.5pt (#455), giving the name 4.5pt more
    /// room because the same `HStack` spacing sits on both sides of it. The
    /// Figma fixture placed the name at x=28.5; the phone read made the tighter
    /// x=26.25 start the controlling evidence instead.
    static let iconWidth: CGFloat = 24
    static let iconGap: CGFloat = 2.25

    /// SF Pro Regular, one size for the habit name and every weekday letter.
    static let textSize: CGFloat = 12
    /// The largest a habit name may grow when the reader has asked for larger
    /// text and given up the icon column to get it (#567, `LargeTextPolicy`).
    /// A name at 20pt in a 98pt column reads about six characters; past that
    /// the row would be an ellipsis beside a track. Nothing else reads it —
    /// at the default type size, or with the setting off, the name is
    /// `textSize` exactly.
    static let textSizeCap: CGFloat = 20
    /// The habit icon is the same size as the name it sits beside (#455), and
    /// derived from it rather than written down so the two cannot drift.
    ///
    /// #404 took it from two points larger than the name to two points smaller.
    /// The phone read that result as too small; equality is the requested
    /// relationship rather than a third independent size.
    ///
    /// The icon *column* is unchanged at `iconWidth` 24: the glyph changed, the
    /// space it sits in did not, so nothing after it moves.
    static let iconSize: CGFloat = textSize

    /// How far a habit name may run before it is truncated: the label column,
    /// less the icon and the one gap between icon and name.
    ///
    ///     label 98 − icon 24 − iconGap 2.25 = 71.75
    ///
    /// This constant used to read `(labelWidth + labelGap) - iconWidth -
    /// iconGap` = 73.5, and described a name as "allowed to overflow the label
    /// column and use the gap before the track". **The app never did that**
    /// (#412). Both surfaces that draw a name hold the whole label to the
    /// label column — `HabitRowView`'s `.frame(width: labelWidth)` and
    /// `WeekWidgetView`'s. Before #475 that column was an
    /// `HStack(spacing: iconGap)` containing the icon, name and trailing
    /// `Spacer`, so SwiftUI inserted a second 2.25pt gap before an empty
    /// spacer. The arrangement now applies the gap to the icon's trailing edge
    /// instead. The name reaches the label column's own edge while `labelGap`
    /// still keeps it clear of the track.
    ///
    /// #455 halved the shared spacing constant, granting 69.5pt rather than
    /// 65pt while the icon column and track stayed fixed. #475 then removed
    /// the repeated spacing after the name, granting the otherwise-unused
    /// 2.25pt as well. `HabitEditorView` renders this same arrangement for its
    /// truncation measurement rather than copying the number.
    ///
    /// So this is the arrangement's own number, not the design's target. The
    /// design's 73.5 — a name reaching into `labelGap`, which is how the file
    /// fits "Watch Sunset" — is a thing the app does not do, and #412 records
    /// the choice to say what the row grants rather than what the design
    /// wanted. Changing this constant alone would not widen a name: #475
    /// changes the arrangement's one real gap, and the derivation follows it.
    static let nameMaxWidth: CGFloat = labelWidth - iconWidth - iconGap

    /// The weekday header's own row: shorter than a slot row, and its cells are
    /// wider than a slot with almost no gap, because a letter needs the width
    /// and a slot does not.
    static let headerHeight: CGFloat = 14

    /// The month habit name's line box: 14.5pt, the text box the design
    /// authors at y=10 in the 158pt frame (nodes `357:9212` and `357:9301`,
    /// 36 of 392 at 2.48x). It occupies the header position but is not the
    /// week widget's row of weekday letters, so correcting the month never
    /// moves either week surface (#493). It was 18 until 2026-09-05.
    static let monthTitleHeight: CGFloat = 14.5

    /// The air between the month's title box and its first row: 6.5pt, so the
    /// grid starts at `padTop + monthTitleHeight + monthHeaderGap = 31`, where
    /// the design puts it for five rows and six alike (2026-09-05). The
    /// week's `headerGap` is a different number for a different header.
    static let monthHeaderGap: CGFloat = 6.5

    /// Extra space above only the small month widget's title (#527): none,
    /// since 2026-09-05. The title's top is the shared `padTop`, 10pt, where
    /// the design draws it; the 10pt this used to add put the title at 20 and
    /// the grid at 42, and centred the rows in what was left. Kept as a named
    /// zero rather than removed so the month's vertical arithmetic still
    /// reads as three terms in one place.
    static let monthTopInset: CGFloat = 0

    /// The small month's bottom inset: 11pt, the room the design leaves under
    /// six rows (392 − 76.9 − 287.9 at 2.48x). The week families keep the
    /// shared `padBottom`; a month that inherited 14 would either lose its
    /// 20pt pitch at six rows or overflow, and the design does neither.
    static let smallPadBottom: CGFloat = 11

    static func padBottom(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? smallPadBottom : padBottom
    }

    /// How far the row block sits below whatever precedes it, so that it is
    /// centred in the height the header leaves (#368).
    ///
    /// **Declared here because two things read it and a copy would rot.** The
    /// widget centres its rows with this, and `WidgetRenderDiffTests` locates
    /// the band it samples with the same call — a harness that computed its own
    /// offset would keep passing while the widget drifted underneath it, which
    /// is the mirror-copy failure the working rules name.
    ///
    /// Zero when the rows fill the family, which is why a large widget at
    /// capacity is untouched by centring. **That was true of the design frame
    /// and of no phone until #410** — the row block came up a row short on
    /// every real frame, and this split the resulting ~31pt above and below,
    /// which is what a large widget's centred grid actually was. `rowLayout`
    /// makes the block fill the height again, so the offset is zero at capacity
    /// on any frame and this is once more only the short-list case it was
    /// written for. Never negative: an overfull block is cut by `rowCapacity`
    /// before it reaches here, and clamping rather than trusting that keeps the
    /// two independent.
    ///
    /// `contentHeight` is the content box, inside the vertical padding — the
    /// same input `rowCapacity` takes.
    static func rowsOffset(
        contentHeight: CGFloat, slot: CGFloat, rows: Int, hasHeader: Bool
    ) -> CGFloat {
        rowsOffset(
            contentHeight: contentHeight,
            slot: slot,
            gap: rowGap,
            rows: rows,
            headerFootprint: hasHeader ? headerHeight + headerGap : 0
        )
    }

    /// The shared row-block centring calculation (#505).
    ///
    /// The week uses the overload above because its gap and optional header are
    /// fixed. A month has the same geometry with two deliberate differences:
    /// its title has its own line box, and its vertical gap can tighten to keep
    /// six rows inside a real small-widget frame. Taking those values keeps one
    /// centring rule rather than growing a second copy beside the month view.
    static func rowsOffset(
        contentHeight: CGFloat,
        slot: CGFloat,
        gap: CGFloat,
        rows: Int,
        headerFootprint: CGFloat
    ) -> CGFloat {
        let available = contentHeight - headerFootprint
        let block = CGFloat(rows) * slot + CGFloat(max(0, rows - 1)) * gap
        return max(0, (available - block) / 2)
    }

    /// How far a week widget's header-and-rows group sits from the top (#517).
    ///
    /// This is deliberately a sibling of `rowsOffset`, even though the two
    /// reduce to the same arithmetic for the week's fixed metrics. Their
    /// meanings differ: `rowsOffset` places rows in the space left *after* a
    /// title or header, while this places the header inside the centred group.
    /// Keeping the APIs distinct prevents the month's title from travelling
    /// when only the weekday header was asked to move.
    static func groupOffset(
        contentHeight: CGFloat, slot: CGFloat, rows: Int, hasHeader: Bool
    ) -> CGFloat {
        let header = hasHeader ? headerHeight + headerGap : 0
        let rowsHeight = CGFloat(rows) * slot + CGFloat(max(0, rows - 1)) * rowGap
        return max(0, (contentHeight - header - rowsHeight) / 2)
    }

    /// How many habit rows fit in a given height.
    ///
    /// Derived rather than written down, so it cannot drift when the padding,
    /// the gap or the slot changes — all three have moved at least once, and
    /// #331 moved all three at once. Ten for the large family and four for the
    /// medium, asserted by tests rather than written down anywhere.
    ///
    /// `height` is the content box, inside the vertical padding.
    static func rowCapacity(height: CGFloat, slot: CGFloat, hasHeader: Bool) -> Int {
        guard slot > 0 else { return 0 }
        let available = height - (hasHeader ? headerHeight + headerGap : 0)
        guard available > 0 else { return 0 }
        // n slots and n-1 gaps fit in `available`.
        return max(0, Int((available + rowGap) / (slot + rowGap)))
    }

    // The background lives in `GlowPalette.widgetSurface` (#333), and the note
    // that used to sit here is worth keeping rather than deleting: the design
    // drew a gradient container, the widget followed it for a while, and on a
    // real home screen it read as a panel sitting on the wallpaper rather than
    // marks floating on it. That was measured on hardware and it stands.
    //
    // #333 is a decision on top of it. The marks became sockets pressed into a
    // surface (#332), and a socket needs a surface — so the panel is the point
    // now rather than the problem. What has not changed is that the reading was
    // real, so if the glass ever looks like a panel again, this is the note
    // saying that outcome was seen once already.
}
