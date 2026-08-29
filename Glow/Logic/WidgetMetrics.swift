import CoreGraphics
import WidgetKit

/// The large widget's layout, in the design file's own numbers.
///
/// Lives in `Glow/Logic` rather than in the widget target because the app needs
/// one number out of it: how many rows the widget can show. The grid marks that
/// boundary, and a second copy of the figure in the app would be a copy that
/// could drift.
///
/// Node `83:1676` is authored at 1x — 338 × 354, which is the real point size of
/// a large widget on this phone — so these are read straight off it rather than
/// halved from a 2x frame or measured off a render.
///
/// Every value here is a *design* number. Nothing is derived from a screenshot
/// and nothing is rounded to something tidier; where the file is on a half point
/// this is too, because half a point is a real pixel at 2x and two of them at 3x.
enum WidgetMetrics {
    /// The large widget's own size, on a 6.1" iPhone. The design file is
    /// authored at exactly this, at 1x.
    static let largeWidth: CGFloat = 338
    static let largeHeight: CGFloat = 354

    /// A small widget's own size, on the same phone. Square, and the width the
    /// medium and large families share is two of these plus the gap between
    /// them.
    static let smallSide: CGFloat = 158

    /// What the system gives each family on a 6.1" iPhone.
    ///
    /// One list, three readers: the render harness renders every family at its
    /// own size, the Widgets tab previews the real views at theirs (#210), and
    /// `largeRowCapacity` above is the same numbers by another name. A preview
    /// at a size no phone gives is a preview of a layout nobody sees — the slot
    /// size falls out of the track width, so a widget drawn 20pt narrow is not
    /// the same widget slightly smaller.
    ///
    /// Sizes do vary by device; this is the phone the design is authored
    /// against, and the previews scale from here rather than measuring the
    /// screen they are on.
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

    /// How many rows a large widget shows.
    ///
    /// Ten since #331, and derived rather than written down — every input to it
    /// has moved at least once. The app reads this to mark where its grid stops
    /// being visible on the home screen.
    static var largeRowCapacity: Int {
        let track = largeWidth - padLeading - padTrailing - labelWidth - labelGap
        return rowCapacity(
            height: largeHeight - padTop - padBottom,
            slot: SlotLayout.slotHeight(trackWidth: track),
            hasHeader: true
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
    /// cells, so it is inset evenly. Node `234:11216` puts `Frame 14` at x=14
    /// in a 158pt frame, 14 either side.
    ///
    /// Applying the week's 6/14 here shifted the whole grid 8pt left and gave
    /// it 138pt of track where the file draws 130.
    static let smallPad: CGFloat = 14

    /// The leading inset for a family. Small is symmetric; the rest are not.
    static func padLeading(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? smallPad : padLeading
    }

    /// The trailing inset for a family. Both answers are 14 today, and it is
    /// still asked rather than assumed: the week's 14 is the optical pair to
    /// its 6, and the month's is half a symmetric inset. They agree by
    /// coincidence, not by derivation.
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
    /// **`rowGap` is still not a spacing number.** It is set by how far a halo
    /// spills out of a row, and closing it would put each row's light into its
    /// neighbour. It moved from 10 to 8 because the whole grid rescaled, not
    /// because it was slack to be taken.
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
    /// The file places the name at x=28.5 with the symbol at x=0, so the icon
    /// column and the space after it have to add up to exactly that or every
    /// habit name in the widget sits a point off.
    static let iconWidth: CGFloat = 24
    static let iconGap: CGFloat = 4.5

    /// SF Pro Regular, one size for the habit name and every weekday letter.
    static let textSize: CGFloat = 12
    /// The habit icon is two points smaller than the name it sits beside, and
    /// derived from it rather than written down (#404).
    ///
    /// It used to be `textSize + 2`, which drew the glyph 17% *larger* than the
    /// name beside it — the opposite of what the label reads as. The brief was
    /// "2 steps smaller as the font", and this file has no step scale to count
    /// on: `textSize` is a literal point size, not a Dynamic Type style. So the
    /// most literal reading is the one taken — two points below the text — and
    /// it is written as an expression so that moving `textSize` moves this with
    /// it instead of silently reopening the gap.
    ///
    /// The icon *column* is unchanged at `iconWidth` 24: the glyph shrank, the
    /// space it sits in did not, so nothing after it moves and `nameMaxWidth`
    /// is untouched.
    static let iconSize: CGFloat = textSize - 2

    /// How far a habit name may run before it is truncated.
    ///
    /// Not the label column — a name is allowed to overflow it and use the gap
    /// before the track, which is how the design fits "Watch Sunset". The limit
    /// is where the track begins, so a name can never collide with the grid:
    ///
    ///     (label 98 + gap 4) − icon 24 − iconGap 4.5 = 73.5
    ///
    /// The longest name in the design measures 79, which now *does* reach it —
    /// "Watch Sunset" truncates where it used to fit. That is the cost of the
    /// tighter label gap and it is the design's own number (§8.5), not a
    /// regression to correct by widening the limit: the limit is where the
    /// track begins, and a name past it collides with the grid.
    static let nameMaxWidth: CGFloat = (labelWidth + labelGap) - iconWidth - iconGap

    /// The weekday header's own row: shorter than a slot row, and its cells are
    /// wider than a slot with almost no gap, because a letter needs the width
    /// and a slot does not.
    static let headerHeight: CGFloat = 14

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
    /// capacity is untouched by centring. Never negative: an overfull block is
    /// cut by `rowCapacity` before it reaches here, and clamping rather than
    /// trusting that keeps the two independent.
    ///
    /// `contentHeight` is the content box, inside the vertical padding — the
    /// same input `rowCapacity` takes.
    static func rowsOffset(
        contentHeight: CGFloat, slot: CGFloat, rows: Int, hasHeader: Bool
    ) -> CGFloat {
        let header = hasHeader ? headerHeight + headerGap : 0
        let available = contentHeight - header
        let block = CGFloat(rows) * slot + CGFloat(max(0, rows - 1)) * rowGap
        return max(0, (available - block) / 2)
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
