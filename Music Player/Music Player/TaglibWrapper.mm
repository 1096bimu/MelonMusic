#import <taglib/fileref.h>
#import <taglib/flacfile.h>
#import <taglib/flacpicture.h>
#import <taglib/id3v2tag.h>
#import <taglib/mpegfile.h>
#import <taglib/attachedpictureframe.h>
#import <taglib/mp4coverart.h>
#import <taglib/mp4file.h>
#import <taglib/mp4item.h>
#import <taglib/mp4tag.h>
#import <taglib/rifffile.h>
#import <taglib/tag.h>
#import <taglib/tbytevector.h>
#import <taglib/tpropertymap.h>
#import <taglib/tstring.h>
#import <taglib/wavfile.h>
#import "TaglibWrapper.h"

@implementation TaglibWrapper

+ (nullable NSMutableDictionary *)getMetadata:(NSString *)path
{
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];

    TagLib::FileRef fileRef(path.UTF8String);
    if (fileRef.isNull()) {
        return nil;
    }

    TagLib::Tag *tag = fileRef.tag();
    if (!tag) {
        return nil;
    }

    TagLib::RIFF::WAV::File *waveFile = dynamic_cast<TagLib::RIFF::WAV::File *>(fileRef.file());

    NSString *title = [TaglibWrapper stringFromWchar:tag->title().toCWString()];
    if ((title == nil || [title isEqualToString:@""]) && waveFile) {
        title = [TaglibWrapper stringFromWchar:waveFile->InfoTag()->title().toCWString()];
    }
    [dictionary setValue:title ?: @"" forKey:@"TITLE"];

    NSString *artist = [TaglibWrapper stringFromWchar:tag->artist().toCWString()];
    if ((artist == nil || [artist isEqualToString:@""]) && waveFile) {
        artist = [TaglibWrapper stringFromWchar:waveFile->InfoTag()->artist().toCWString()];
    }
    [dictionary setValue:artist ?: @"" forKey:@"ARTIST"];

    NSString *album = [TaglibWrapper stringFromWchar:tag->album().toCWString()];
    if ((album == nil || [album isEqualToString:@""]) && waveFile) {
        album = [TaglibWrapper stringFromWchar:waveFile->InfoTag()->album().toCWString()];
    }
    [dictionary setValue:album ?: @"" forKey:@"ALBUM"];

    NSString *genre = [TaglibWrapper stringFromWchar:tag->genre().toCWString()];
    if ((genre == nil || [genre isEqualToString:@""]) && waveFile) {
        genre = [TaglibWrapper stringFromWchar:waveFile->InfoTag()->genre().toCWString()];
    }
    [dictionary setValue:genre ?: @"" forKey:@"GENRE"];

    TagLib::PropertyMap properties = fileRef.file()->properties();
    for (TagLib::PropertyMap::ConstIterator property = properties.begin(); property != properties.end(); ++property) {
        for (TagLib::StringList::ConstIterator value = property->second.begin(); value != property->second.end(); ++value) {
            NSString *key = [TaglibWrapper stringFromWchar:property->first.toCWString()];
            NSString *object = [TaglibWrapper stringFromWchar:value->toCWString()];

            if (key != nil && object != nil) {
                [dictionary setValue:object ?: @"" forKey:key];
            }
        }
    }

    return dictionary;
}

+ (nullable NSData *)getAlbumArtwork:(NSString *)path
{
    NSData *flacArtwork = [TaglibWrapper getFlacAlbumArtwork:path];
    if (flacArtwork != nil) {
        return flacArtwork;
    }

    NSData *mpegArtwork = [TaglibWrapper getMpegAlbumArtwork:path];
    if (mpegArtwork != nil) {
        return mpegArtwork;
    }

    return [TaglibWrapper getMp4AlbumArtwork:path];
}

+ (nullable NSData *)getFlacAlbumArtwork:(NSString *)path
{
    TagLib::FLAC::File file(path.UTF8String);
    if (!file.isValid()) {
        return nil;
    }

    TagLib::List<TagLib::FLAC::Picture *> pictures = file.pictureList();
    TagLib::FLAC::Picture *fallbackPicture = nullptr;

    for (TagLib::List<TagLib::FLAC::Picture *>::ConstIterator picture = pictures.begin(); picture != pictures.end(); ++picture) {
        if ((*picture)->type() == TagLib::FLAC::Picture::FrontCover) {
            return [TaglibWrapper dataFromByteVector:(*picture)->data()];
        }

        if (fallbackPicture == nullptr) {
            fallbackPicture = *picture;
        }
    }

    if (fallbackPicture != nullptr) {
        return [TaglibWrapper dataFromByteVector:fallbackPicture->data()];
    }

    return nil;
}

+ (nullable NSData *)getMpegAlbumArtwork:(NSString *)path
{
    TagLib::MPEG::File file(path.UTF8String);
    if (!file.isValid() || file.ID3v2Tag() == nullptr) {
        return nil;
    }

    TagLib::ID3v2::FrameList pictures = file.ID3v2Tag()->frameList("APIC");
    TagLib::ID3v2::AttachedPictureFrame *fallbackPicture = nullptr;

    for (TagLib::ID3v2::FrameList::ConstIterator frame = pictures.begin(); frame != pictures.end(); ++frame) {
        TagLib::ID3v2::AttachedPictureFrame *picture = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(*frame);
        if (picture == nullptr) {
            continue;
        }

        if (picture->type() == TagLib::ID3v2::AttachedPictureFrame::FrontCover) {
            return [TaglibWrapper dataFromByteVector:picture->picture()];
        }

        if (fallbackPicture == nullptr) {
            fallbackPicture = picture;
        }
    }

    if (fallbackPicture != nullptr) {
        return [TaglibWrapper dataFromByteVector:fallbackPicture->picture()];
    }

    return nil;
}

+ (nullable NSData *)getMp4AlbumArtwork:(NSString *)path
{
    TagLib::MP4::File file(path.UTF8String);
    if (!file.isValid() || file.tag() == nullptr) {
        return nil;
    }

    TagLib::MP4::Item coverItem = file.tag()->item("covr");
    TagLib::MP4::CoverArtList covers = coverItem.toCoverArtList();
    if (covers.isEmpty()) {
        return nil;
    }

    return [TaglibWrapper dataFromByteVector:covers.front().data()];
}

+ (NSData *)dataFromByteVector:(const TagLib::ByteVector &)byteVector
{
    return [NSData dataWithBytes:byteVector.data() length:byteVector.size()];
}

+ (nullable NSString *)stringFromWchar:(const wchar_t *)charText
{
    if (charText == nullptr || wcslen(charText) == 0) {
        return nil;
    }

    return [[NSString alloc] initWithBytes:charText
                                    length:wcslen(charText) * sizeof(*charText)
                                  encoding:NSUTF32LittleEndianStringEncoding];
}

@end
