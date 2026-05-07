//
//  MusicTrack.swift
//  Music Player
//
//  Created by Chen on 2026-05-05.
//

import Foundation
import SwiftData

@Model
final class MusicTrack {
    @Attribute(.unique) var relativePath: String
    var fileName: String
    var directory: String
    var title: String
    var artist: String
    var albumArtist: String?
    var album: String
    var genre: String
    var fileSize: Int64

    init(
        relativePath: String,
        fileName: String,
        directory: String,
        title: String,
        artist: String,
        albumArtist: String? = nil,
        album: String,
        genre: String,
        fileSize: Int64
    ) {
        self.relativePath = relativePath
        self.fileName = fileName
        self.directory = directory
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.fileSize = fileSize
    }

    var displayTitle: String {
        title.isEmpty ? fileName : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }

    var displayAlbumArtist: String {
        guard let albumArtist, !albumArtist.isEmpty else {
            return "Unknown Album Artist"
        }

        return albumArtist
    }

    var displayAlbum: String {
        album.isEmpty ? "Unknown Album" : album
    }
}
