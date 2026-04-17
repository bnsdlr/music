//! MusicBrainz Web Service v2 — JSON response structs

const std = @import("std");

const mb = @import("root.zig");
const iso = @import("iso.zig");

const MBID = mb.MBID;

// enum?
const Gender = []const u8;
const End = ?[]const u8;
const Begin = ?[]const u8;
const Direction = enum {forward, backward};

pub const Error = struct {
    @"error": []const u8,
    help: []const u8,
};

// make this enum?: City, Subdivision, type of, District, Country
pub const Type = []const u8;

// Area {{{

/// Doc: https://musicbrainz.org/doc/Area
pub const AreaType = enum {
    /// Country is used for areas included (or previously included) in ISO
    /// 3166-1, e.g. United States.
    Country,
    /// Subdivision is used for the main administrative divisions of a country,
    /// e.g. California, Ontario, Okinawa. These are considered when displaying
    /// the parent areas for a given area.
    Subdivision,
    /// County is used for smaller administrative divisions of a country which
    /// are not the main administrative divisions but are also not
    /// municipalities, e.g. counties in the USA. These are not considered when
    /// displaying the parent areas for a given area.
    County,
    /// Municipality is used for small administrative divisions which, for
    /// urban municipalities, often contain a single city and a few surrounding
    /// villages. Rural municipalities typically group several villages
    /// together.
    Municipality,
    /// City is used for settlements of any size, including towns and villages.
    City,
    /// District is used for a division of a large city, e.g. Queens.
    District,
    /// Island is used for islands and atolls which don't form subdivisions of
    /// their own, e.g. Skye. These are not considered when displaying the
    /// parent areas for a given area.
    Island,
};

pub const AreaRef = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": AreaType,
    @"type-id": MBID,
    @"iso-3166-1-codes": []Iso31661Code,
    @"iso-3166-2-codes": []Iso31662Code,
    @"iso-3166-3-codes": []Iso31663Code,
};

pub const Area = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": AreaType,
    @"type-id": MBID,
    @"iso-3166-1-codes": []Iso31661Code,
    @"iso-3166-2-codes": []Iso31662Code,
    @"iso-3166-3-codes": []Iso31663Code,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    relations: ?[]Relation = null,
};

// }}}

// Artist {{{

/// Doc: https://musicbrainz.org/doc/Artist
///
/// The type is used to state whether an artist is a person, a group, or
/// something else.
///
/// Note that not every ensemble related to classical music is an orchestra or
/// choir. The Borodin Quartet and The Hilliard Ensemble, for example, are
/// simply groups.
pub const ArtistType = enum {
    /// This indicates an individual person.
    Person,
    /// This indicates a group of people that may or may not have a distinctive name.
    Group,
    /// This indicates an orchestra (a large instrumental ensemble).
    Orchestra,
    /// This indicates a choir/chorus (a large vocal ensemble).
    Choir,
    /// This indicates an individual fictional character.
    Character,
    /// Anything which does not fit into the above categories.
    Other,
};

/// Lightweight artist reference used inside credits and relations.
pub const ArtistRef = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": ArtistType,
    @"type-id": MBID,
};

pub const Artist = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": ArtistType,
    @"type-id": MBID,
    gender: Gender,
    @"gender-id": MBID,
    country: Iso31661Code,
    area: AreaRef,
    @"begin-area": AreaRef,
    @"end-area": AreaRef,
    @"life-span": LifeSpan,
    ipis: [][]const u8,
    isnis: [][]const u8,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    rating: ?Rating = null,
    @"user-ratings": ?UserRating = null,
    recordings: ?[]Recording = null,
    releases: ?[]Release = null,
    @"release-groups": ?[]ReleaseGroup = null,
    works: ?[]Work = null,
    relations: ?[]Relation = null,
};

// }}}

// Collection {{{

/// Doc: https://musicbrainz.org/doc/Collections
pub const CollectionType = []const u8;

pub const Collection = struct {
    id: MBID,
    name: []const u8,
    editor: []const u8,
    @"entity-type": []const u8,
    @"type": CollectionType,
    @"type-id": MBID,
    // inc= fields:
    @"user-collections": ?[]Collection = null,
};

// }}}

// Event {{{

/// Doc: https://musicbrainz.org/doc/Event
///
/// The type describes what kind of event the event is. The possible values are:
pub const EventType = enum {
    // An individual concert by a single artist or collaboration, often with
    // supporting artists who perform before the main act.
    @"Concert",
    // An event where a number of different acts perform across the course of
    // the day. Larger festivals may be spread across multiple days.
    @"Festival",
    // A performance of one or more plays, musicals, operas, ballets or other
    // similar works for the stage in their staged form (as opposed to a
    // concert performance without staging).
    @"Stage performance",
    // An event that is focused on the granting of prizes, but often includes
    // musical performances in between the awarding of said prizes, especially
    // for musical awards.
    @"Award ceremony",
    // A party, reception or other event held specifically for the launch of a
    // release.
    @"Launch event",
    // A convention, expo or trade fair is an event which is not typically
    // orientated around music performances, but can include them as side
    // activities.
    @"Convention/Expo",
    // A masterclass or clinic is an event where an artist meets with a small
    // to medium-sized audience and instructs them individually and/or takes
    // questions intended to improve the audience members' playing skills.
    @"Masterclass/Clinic",
};

pub const EventRef = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": EventType,
    @"type-id": MBID,
};

pub const Event = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": EventType,
    @"type-id": MBID,
    cancelled: bool,
    @"life-span": LifeSpan,
    time: []const u8,
    setlist: []const u8,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    rating: ?Rating = null,
    @"user-ratings": ?UserRating = null,
    relations: ?[]Relation = null,
};

// }}}

// Genre {{{

/// Doc: https://musicbrainz.org/doc/Genre
pub const GenreType = []const u8;

pub const GenreRef = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
};

pub const GenreEntity = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    // Note: genres do not support relations or most inc= parameters.
};

// }}}

// Instrument {{{

/// Doc: https://musicbrainz.org/doc/Instrument
/// 
/// The type categorises the instrument by the way the sound is created, similar to the Hornbostel-Sachs classification. The possible values are:
pub const InstrumentType = enum {
    /// An aerophone, i.e. an instrument where the sound is created by
    /// vibrating air. The instrument itself does not vibrate.
    @"Wind instrument",
    /// A chordophone, i.e. an instrument where the sound is created by the
    /// vibration of strings.
    @"String instrument",
    /// An idiophone, i.e. an instrument where the sound is produced by the
    /// body of the instrument vibrating, or a drum (most membranophones) where
    /// the sound is produced by a stretched membrane which is struck or
    /// rubbed.
    @"Percussion instrument",
    /// An electrophone, i.e. an instrument where the sound is created with
    /// electricity.
    @"Electronic instrument",
    /// A grouping of related but different instruments, like the different
    /// violin-like instruments.
    Family,
    /// A standard grouping of instruments often played together, like a string
    /// quartet.
    Ensemble,
    /// An instrument which doesn't fit in the categories above.
    @"Other instrument",
};

pub const InstrumentRef = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": InstrumentType,
    @"type-id": MBID,
};

pub const Instrument = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": InstrumentType,
    @"type-id": MBID,
    description: []const u8,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    relations: ?[]Relation = null,
};

// }}}

// Label {{{

/// Doc: https://musicbrainz.org/doc/Label/Type
pub const LabelType = enum {
    /// imprint: should be used where the label is just a logo (usually either
    /// created by a company for a specific product line, or where a former
    /// company’s logo is still used on releases after the company was closed
    /// or purchased, or both)
    ///
    /// example: RCA Red Seal
    imprint,
    /// original production: should be used for labels producing entirely new
    /// releases
    ///
    /// example: Riverside Records
    @"original production",
    /// bootleg production: should be used for known bootlegs labels (as in
    /// "not sanctioned by the rights owner(s) of the released work")
    ///
    /// example: Charly Records
    @"bootleg production",
    /// reissue production: should be used for labels specializing in catalog
    /// reissues
    ///
    /// example: Rhino
    @"reissue production",
    /// distributor: should be used for companies mainly distributing other
    /// labels production, often in a specific region of the world
    ///
    /// example: ZYX, which distributes in Europe most jazz records in the
    /// Concord Music Group catalog.
    @"distributor",
    /// holding: should be used for holdings, conglomerates or other financial
    /// entities whose main activity is not to produce records, but to manage a
    /// large set of recording labels owned by them
    ///
    /// example: Concord Music Group
    holding,
    /// rights society: A rights society is an organization which collects
    /// royalties on behalf of the artists. This type is designed to be used
    /// with the rights society relationship type rather than as a normal
    /// release label.
    ///
    /// example: GEMA
    @"rights society",
    /// publisher: A company that primarily deals with music publishing
    /// (managing the copyrights, licensing and royalties for musical
    /// compositions).
    ///
    /// example: Boosey & Hawkes
    publisher,
    /// manufacturer: A company that manufactures physical releases (such as
    /// pressing CDs or vinyl records). This type is designed to be used with
    /// relationships such as manufactured, pressed and glass mastered, rather
    /// than as a normal release label.
    manufacturer,
    /// broadcaster: An organization that mostly concentrates on broadcasting
    /// audio or video content, be it on television, radio or the internet.
    ///
    /// example: BBC Radio 3
    broadcaster,
};

pub const LabelRef = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": LabelType,
    @"type-id": MBID,
    @"label-code": u32,
};

pub const Label = struct {
    id: MBID,
    name: []const u8,
    @"sort-name": []const u8,
    disambiguation: []const u8,
    @"type": LabelType,
    @"type-id": MBID,
    country: Iso31661Code,
    area: AreaRef,
    @"label-code": u32,
    @"life-span": LifeSpan,
    ipis: [][]const u8,
    isnis: [][]const u8,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    rating: ?Rating = null,
    @"user-ratings": ?UserRating = null,
    releases: ?[]Release = null,
    relations: ?[]Relation = null,
};

// }}}

// Place {{{

/// Doc: https://musicbrainz.org/doc/Place
///
/// The type categorises the place based on its primary function. The possible values are:
pub const PlaceType = enum {
    /// A place designed for non-live production of music, typically a recording studio.
    @"Studio",
    /// A place that has live artistic performances as one of its primary functions, such as a concert hall.
    @"Venue",
    /// A large, permanent outdoor stage, typically with a fixed seating area.
    @"Amphitheatre",
    /// A small venue (such as a jazz club, nightclub or pub) that hosts concerts and social events. May or may not have a dedicated stage or seating.
    @"Club",
    /// An indoor performance facility with fixed seating, whether for music (usually, but not always, classical music) or theatre.
    @"Concert hall / Theatre",
    /// A temporary outdoor stage erected for a music festival or other similar event.
    @"Festival stage",
    /// A place whose main purpose is to host outdoor sport events, typically consisting of a pitch surrounded by a structure for spectators with no roof, or a roof which can be retracted.
    Stadium,
    /// A place consisting of a large enclosed area with a central event space surrounded by tiered seating for spectators, which can be used for indoor sports, concerts and other entertainment events.
    @"Indoor arena",
    /// A school, university or other similar educational institution (especially, but not only, one where music is taught)
    @"Educational institution",
    /// A (usually green) space kept available for recreation in an otherwise built and populated area.
    Park,
    /// A place mostly designed and used for religious purposes, like a church, cathedral or synagogue.
    @"Religious building",
    /// A place (generally a factory) at which physical media are manufactured.
    @"Pressing plant",
    /// Anything which does not fit into the above categories.
    Other,
};

pub const PlaceRef = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": PlaceType,
    @"type-id": MBID,
};

pub const Place = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": PlaceType,
    @"type-id": MBID,
    address: []const u8,
    area: AreaRef,
    coordinates: Coordinates,
    @"life-span": LifeSpan,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    relations: ?[]Relation = null,

    pub const Coordinates = struct {
        latitude: f64,
        longitude: f64,
    };
};

// }}}

// Recording {{{

/// Doc: https://musicbrainz.org/doc/Recording
pub const RecordingType = []const u8;

pub const RecordingRef = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    length: u32, // milliseconds
    video: bool,
};

pub const Recording = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    length: u32, // milliseconds
    video: bool,
    @"first-release-date": []const u8,
    // inc= fields:
    @"artist-credit": ?[]ArtistCreditEntry = null,
    isrcs: ?[][]const u8 = null,
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    rating: ?Rating = null,
    @"user-ratings": ?UserRating = null,
    releases: ?[]Release = null,
    @"release-groups": ?[]ReleaseGroup = null,
    relations: ?[]Relation = null,
};

// }}}

// Release {{{

/// Doc: https://musicbrainz.org/doc/Release
pub const ReleaseType = []const u8;

/// Doc: https://musicbrainz.org/doc/Release
///
/// The status describes how "official" a release is.
pub const ReleaseStatus = enum {
    // Any release officially sanctioned by the artist and/or their record
    // company. Most releases will fit into this category.
    official,
    // A give-away release or a release intended to promote an upcoming
    // official release (e.g. pre-release versions, releases included with a
    // magazine, versions supplied to radio DJs for air-play).
    promotion,
    // An unofficial/underground release that was not sanctioned by the artist
    // and/or the record company. This includes unofficial live recordings and
    // pirated releases.
    bootleg,
    // An alternate version of a release where the titles have been changed.
    // These don't correspond to any real release and should be linked to the
    // original release using the transl(iter)ation relationship.
    @"pseudo-release",
    // An official release that was actively withdrawn from circulation by the
    // artist and/or their record company after being released, whether to
    // replace it with a new version or to retire it altogether. This does not
    // include releases that have reached the end of their “natural” life
    // cycle, such as being sold out and out of print.
    withdrawn,
    // A previously official release that was actively expunged from an artist
    // or records company’s discography. This should not be used in cases where
    // the release was just withdrawn, there needs to be known artist or label
    // intent to disown the release and no longer consider it part of their
    // discography. If it is unclear, use Withdrawn.
    expunged,
    // A planned official release that was cancelled before being released, but
    // for which enough info is known to still confidently list it (e.g. it was
    // available for preorder).
    cancelled,
};

pub const ReleaseRef = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    status: []const u8,
    @"status-id": MBID,
};

pub const Release = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    status: []const u8,
    @"status-id": MBID,
    date: []const u8,
    country: Iso31661Code,
    barcode: []const u8,
    asin: []const u8,
    quality: []const u8, // "low" | "normal" | "high"
    packaging: []const u8,
    @"packaging-id": MBID,
    @"text-representation": TextRepresentation,
    @"release-events": []ReleaseEvent,
    @"cover-art-archive": CoverArtArchive,
    // inc= fields:
    @"artist-credit": ?[]ArtistCreditEntry = null,
    @"release-group": ?ReleaseGroup = null,
    media: ?[]Medium = null,
    @"label-info": ?[]LabelInfo = null,
    collections: ?[]Collection = null,
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    relations: ?[]Relation = null,
};

// }}}

// ReleaseGroup {{{

/// Doc: https://musicbrainz.org/doc/Release_Group/Type
/// 
/// The type of a release group describes what kind of release group it is. It
/// is divided in two: a release group can have a "main" type and an
/// unspecified number of extra types.
pub const ReleaseGroupType = enum {
    // Primary types
    /// An album, perhaps better defined as a "Long Play" (LP) release,
    /// generally consists of previously unreleased material (unless this type
    /// is combined with secondary types which change that, such as
    /// "Compilation").
    Album,
    /// A single has different definitions depending on the market it is
    /// released for.
    /// 
    /// In the US market, a single typically has one main song and possibly a
    /// handful of additional tracks or remixes of the main track; the single
    /// is usually named after its main song; the single is primarily released
    /// to get radio play and to promote release sales.
    ///
    /// The U.K. market (also Australia and Europe) is similar to the US
    /// market, however singles are often released as a two disc set, with each
    /// disc sold separately. They also sometimes have a longer version of the
    /// single (often combining the tracks from the two disc version) which is
    /// very similar to the US style single, and this is referred to as a
    /// "maxi-single". (In some cases the maxi-single is longer than the
    /// release the single comes from!)
    ///
    /// The Japanese market is much more single driven. The defining factor is
    /// typically the length of the single and the price it is sold at. Up
    /// until 1995 it was common that these singles would be released using a
    /// mini-cd format, which is basically a much smaller CD typically 8 cm in
    /// diameter. Around 1995 the 8cm single was phased out, and the standard
    /// 12cm CD single is more common now; generally re-releases of singles
    /// from pre-1995 will be released on the 12cm format, even if they were
    /// originally released on the 8cm format. Japanese singles often come with
    /// karaoke ("instrumental") versions of the songs and also have
    /// maxi-singles like the UK with remixed versions of the songs. Sometimes
    /// a maxi-single will have more tracks than an EP but as it's all
    /// alternate versions of the same 2-3 songs it is still classified as a
    /// single.
    ///
    /// There are other variations of the single called a "split single" where
    /// songs by two different artists are released on the one disc, typically
    /// vinyl. The term "B-Side" comes from the era when singles were released
    /// on 7 inch (or sometimes 12 inch) vinyl with a song on each side, and so
    /// side A is the track that the single is named for, and the other side -
    /// side B - would contain a bonus song, or sometimes even the same song.
    Single,
    /// An EP is a so-called "Extended Play" release and often contains the
    /// letters EP in the title. Generally an EP will be shorter than a full
    /// length release (an LP or "Long Play") and the tracks are usually
    /// exclusive to the EP, in other words the tracks don't come from a
    /// previously issued release. EP is fairly difficult to define; usually it
    /// should only be assumed that a release is an EP if the artist defines it
    /// as such.
    EP,
    /// An episodic release that was originally broadcast via radio,
    /// television, or the Internet, including podcasts.
    Broadcast,
    /// Any release that does not fit or can't decisively be placed in any of
    /// the categories above.
    Other,

    // Secondary types

    /// A compilation, for the purposes of the MusicBrainz database, covers the
    /// following types of releases:
    ///
    /// a collection of recordings from various old sources (not necessarily
    /// released) combined together. For example a "best of", retrospective or
    /// rarities type release.
    ///
    /// a various artists song collection, usually based on a general theme
    /// ("Songs for Lovers"), a particular time period ("Hits of 1998"), or
    /// some other kind of grouping ("Songs From the Movies", the "Café del
    /// Mar" series, etc).
    ///
    /// The MusicBrainz project does not generally consider the following to be
    /// compilations:
    ///
    /// * a reissue of an album, even if it includes bonus tracks.
    ///
    /// * a tribute release containing covers of music by another artist.
    ///
    /// * a classical release containing new recordings of works by a classical
    ///   artist.
    ///
    /// * a split release containing new music by several artists
    ///
    /// Compilation should be used in addition to, not instead of, other types:
    /// for example, a various artists soundtrack using pre-released music
    /// should be marked as both a soundtrack and a compilation. As a general
    /// rule, always select every secondary type that applies.
    Compilation,
    /// A soundtrack is the musical score to a movie, TV series, stage show,
    /// video game, or other medium. Video game CDs with audio tracks should be
    /// classified as soundtracks because the musical properties of the CDs are
    /// more interesting to MusicBrainz than their data properties.
    Soundtrack,
    /// Non-music spoken word releases.
    Spokenword,
    /// An interview release contains an interview, generally with an artist.
    Interview,
    /// An audiobook is a book read by a narrator without music.
    Audiobook,
    /// An audio drama is an audio-only performance of a play (often, but not
    /// always, meant for radio). Unlike audiobooks, it usually has multiple
    /// performers rather than a main narrator.
    @"Audio drama",
    /// A release that was recorded live.
    Live,
    /// A release that primarily contains remixed material.
    Remix,
    /// A DJ-mix is a sequence of several recordings played one after the
    /// other, each one modified so that they blend together into a continuous
    /// flow of music. A DJ mix release requires that the recordings be
    /// modified in some manner, and the DJ who does this modification is
    /// usually (although not always) credited in a fairly prominent way.
    @"DJ-mix",
    /// Promotional in nature (but not necessarily free), mixtapes and street
    /// albums are often released by artists to promote new artists, or
    /// upcoming studio albums by prominent artists. They are also sometimes
    /// used to keep fans' attention between studio releases and are most
    /// common in rap & hip hop genres. They are often not sanctioned by the
    /// artist's label, may lack proper sample or song clearances and vary
    /// widely in production and recording quality. While mixtapes are
    /// generally DJ-mixed, they are distinct from commercial DJ mixes (which
    /// are usually deemed compilations) and are defined by having a
    /// significant proportion of new material, including original production
    /// or original vocals over top of other artists' instrumentals. They are
    /// distinct from demos in that they are designed for release directly to
    /// the public and fans; not to labels.
    @"Mixtape/Street",
    /// A demo is typically distributed for limited circulation or reference
    /// use, rather than for general public release. It is a way for artists to
    /// pass along their music to record labels, producers, DJs or other
    /// artists.
    Demo,
    /// A release mostly consisting of field recordings (such as nature sounds
    /// or city/industrial noise).
    @"Field recording",
};

pub const ReleaseGroupRef = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    @"primary-type": ReleaseGroupType,
    @"primary-type-id": MBID,
};

pub const ReleaseGroup = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    @"primary-type": ReleaseGroupType,
    @"primary-type-id": MBID,
    @"secondary-types": [][]const u8,
    @"secondary-type-ids": []MBID,
    @"first-release-date": []const u8,
    // inc= fields:
    @"artist-credit": ?[]ArtistCreditEntry = null,
    releases: ?[]Release = null,
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    rating: ?Rating = null,
    @"user-ratings": ?UserRating = null,
    relations: ?[]Relation = null,
};

// }}}

// Series {{{

/// Doc: https://musicbrainz.org/doc/Series
///
/// The type primarily describes what type of entity the series contains.
pub const SeriesType = enum {
    /// A series of release groups.
    @"Release group series",
    /// A series of release groups honoured by the same award.
    @"Release group award",
    /// A series of release groups containing episodes of the same podcast series.
    Podcast,
    /// A series of releases.
    @"Release series",
    /// A series of recordings.
    @"Recording series",
    /// A series of recordings honoured by the same award.
    @"Recording award",
    /// A series of works.
    @"Work series",
    /// A series of works which form a catalogue of classical compositions.
    Catalogue,
    /// A series of works honoured by the same award.
    @"Work award",
    /// A series of artists.
    @"Artist series",
    /// A series of artists honored by the same award.
    @"Artist award",
    /// A series of events.
    @"Event series",
    /// A series of related concerts by an artist in different locations.
    Tour,
    /// A recurring festival, usually happening annually in the same location.
    Festival,
    /// A series of performances of the same show at the same venue.
    Run,
    /// A series of related concerts by an artist in the same location.
    Residency,
    /// A series of award ceremonies, usually one per year.
    @"Award ceremony",
};

pub const SeriesRef = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": SeriesType,
    @"type-id": MBID,
};

pub const Series = struct {
    id: MBID,
    name: []const u8,
    disambiguation: []const u8,
    @"type": SeriesType,
    @"type-id": MBID,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    relations: ?[]Relation = null,
};

// }}}

// Work {{{

/// Doc: https://musicbrainz.org/doc/Work
pub const WorkType = []const u8;

pub const WorkRef = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    @"type": WorkType,
    @"type-id": MBID,
};

pub const Work = struct {
    id: MBID,
    title: []const u8,
    disambiguation: []const u8,
    @"type": WorkType,
    @"type-id": MBID,
    language: []const u8,
    languages: [][]const u8,
    iswcs: [][]const u8,
    attributes: []WorkAttribute,
    // inc= fields:
    aliases: ?[]Alias = null,
    annotation: ?Annotation = null,
    tags: ?[]Tag = null,
    @"user-tags": ?[]UserTag = null,
    genres: ?[]Genre = null,
    @"user-genres": ?[]Genre = null,
    rating: ?Rating = null,
    @"user-ratings": ?UserRating = null,
    relations: ?[]Relation = null,

    pub const WorkAttribute = struct {
        @"type": []const u8,
        @"type-id": MBID,
        value: []const u8,
        @"value-id": MBID,
    };
};

// }}}

// Url {{{

pub const UrlType = []const u8;

pub const UrlRef = struct {
    id: MBID,
    resource: []const u8,
};

pub const Url = struct {
    id: MBID,
    resource: []const u8,
    // inc= fields (relationships only):
    relations: ?[]Relation = null,
};

// }}}

pub const Locale = iso.Alpha2Lowercase;

pub const Iso31661Code = iso.Alpha2;
pub const Iso31662Code = iso.Subdivision;
pub const Iso31663Code = iso.FormerCountry;

// Shared / Primitive types {{{

/// ISO 8601 partial date: "YYYY", "YYYY-MM", or "YYYY-MM-DD".
pub const PartialDate = struct {
    year: ?u16 = null,
    month: ?u8 = null,
    day: ?u8 = null,

    const Self = @This();

    pub fn parse(str: []const u8) error{InvalidCharacter,Overflow}!Self {
        var out: Self = .{};
        var iter = std.mem.splitAny(u8, str, "-");

        var i: usize = 0;
        while (iter.next()) |int_str| : (i += 1) {
            switch (i) {
                0 => out.year = try std.fmt.parseInt(u8, int_str, 10),
                1 => out.month = try std.fmt.parseInt(u8, int_str, 10),
                2 => out.day = try std.fmt.parseInt(u8, int_str, 10),
                else => {},
            }
        }

        return out;
    }
};

pub const UserTag = struct {
    name: []const u8,
    vote: Vote,
};

pub const Vote = enum {
    upvote,
    downvote,
    withdraw,
};

pub const Genre = struct {
    id: MBID,
    name: []const u8,
    count: u32,
    disambiguation: []const u8,
};

pub const Rating = struct {
    value: ?f32,
    @"votes-count": u32,
};

pub const UserRating = struct {
    /// 0-100
    value: u8,
};

pub const Annotation = struct {
    text: []const u8,
};

const Tag = struct {
    count: u32,
    name: []const u8,
};

const Alias = struct {
    name: []const u8,
    @"sort-name": []const u8,
    end: End,
    begin: Begin,
    ended: bool,
    primary: bool,
    @"type-id": MBID,
    @"type": Type,
    locale: Locale,
};

const LifeSpan = struct {
    ended: bool,
    end: End,
    begin: Begin,
};

/// A single credit entry in an artist-credit list.
pub const ArtistCreditEntry = struct {
    artist: ArtistRef,
    /// credited name, may differ from artist.name
    name: []const u8,
    joinphrase: []const u8,
};


// }}}

// Relationships {{{

/// A relationship attribute (e.g. "guitar", "1st violin").
pub const RelationAttribute = struct {
    @"type": []const u8,
    @"type-id": MBID,
    value: []const u8,
    @"value-id": MBID,
    @"credited-as": []const u8,
};

/// A single relationship between the current entity and a target entity.
/// The `target-type` field names which union arm is populated.
pub const Relation = struct {
    @"type": []const u8,
    @"type-id": MBID,
    @"target-type": []const u8,
    direction: Direction, 
    @"ordering-key": u32,
    begin: Begin,
    end: End,
    ended: bool,
    attributes: [][]const u8,
    /// map of attr -> uuid
    @"attribute-ids": std.json.Value, 
    /// map of attr -> value
    @"attribute-values": std.json.Value,
    @"attribute-credits": std.json.Value,

    ref: ?Reference = null,

    pub const Reference = union(enum) {
        area: AreaRef,
        artist: ArtistRef,
        event: EventRef,
        genre: GenreRef,
        instrument: InstrumentRef,
        label: LabelRef,
        place: PlaceRef,
        recording: RecordingRef,
        release: ReleaseRef,
        @"release-group": ReleaseGroupRef,
        series: SeriesRef,
        work: WorkRef,
        url: UrlRef,
    };
};

// }}}

// Release sub-types {{{

pub const LabelInfo = struct {
    @"catalog-number": []const u8,
    label: LabelRef,
};

pub const ReleaseEvent = struct {
    date: []const u8,
    area: AreaRef,
};

pub const Medium = struct {
    title: []const u8,
    position: u32,
    format: []const u8,
    @"format-id": MBID,
    @"track-count": u32,
    @"track-offset": u32,
    tracks: []Track,
    discs: []Disc,
};

pub const Track = struct {
    id: MBID,
    number: []const u8,
    title: []const u8,
    /// milliseconds
    length: u32,
    position: u32,
    recording: Recording,
    @"artist-credit": []ArtistCreditEntry,
};

pub const Disc = struct {
    /// disc ID (not an MBID)
    id: []const u8, 
    sectors: u32,
    @"offset-count": u32,
    offsets: []u32,
};

pub const TextRepresentation = struct {
    language: []const u8,
    script: []const u8,
};

pub const CoverArtArchive = struct {
    artwork: bool,
    count: u32,
    front: bool,
    back: bool,
    darkened: bool,
};

// }}}

// List / Browse / Search response wrappers {{{
// The JSON key for the items array varies by entity (e.g. "artists",
// "releases"). Parse the outer wrapper with the appropriate concrete type.

pub const ArtistList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    artists: []Artist,
};

pub const ReleaseList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    releases: []Release,
};

pub const ReleaseGroupList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    @"release-groups": []ReleaseGroup,
};

pub const RecordingList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    recordings: []Recording,
};

pub const LabelList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    labels: []Label,
};

pub const WorkList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    works: []Work,
};

pub const AreaList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    areas: []Area,
};

pub const EventList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    events: []Event,
};

pub const PlaceList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    places: []Place,
};

pub const SeriesList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    series: []Series,
};

pub const InstrumentList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    instruments: []Instrument,
};

pub const UrlList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    urls: []Url,
};

pub const GenreList = struct {
    created: []const u8,
    count: u32,
    offset: u32,
    genres: []GenreEntity,
};

// }}}

// Non-MBID lookup response wrappers {{{

/// Response to /ws/2/discid/<discid>
pub const DiscIdLookup = struct {
    id: []const u8,
    releases: ?[]Release = null,
    // CD stub fallback — only present when disc ID matches a stub, not a release:
    cdstub: ?CdStub = null,

    pub const CdStub = struct {
        id: []const u8,
        title: []const u8,
        artist: []const u8,
        barcode: []const u8,
        comment: []const u8,
        @"track-count": u32,
    };
};

/// Response to /ws/2/isrc/<isrc>
pub const IsrcLookup = struct {
    isrc: []const u8,
    recordings: []Recording,
};

/// Response to /ws/2/iswc/<iswc>
pub const IswcLookup = struct {
    iswc: []const u8,
    works: []Work,
};

// }}}

test {
    std.testing.refAllDecls(@This());
}

