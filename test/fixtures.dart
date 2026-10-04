/// Response fixtures captured from the live YouTube Music InnerTube API.
///
/// The renderer shapes are preserved verbatim so parser regressions surface
/// here rather than on device. Captured with the iOS music client for search
/// and the iOS client for playback.
///
/// These are Dart raw strings, so JSON escapes are written literally: `\"`
/// and `•` reach the JSON decoder unchanged.
library;

/// Android music client search: `musicTwoColumnItemRenderer` in a shelf.
const String androidMusicSearchResponse = r'''
{"contents":{"sectionListRenderer":{"contents":[{"musicShelfRenderer":{"contents":[{"musicTwoColumnItemRenderer":{
  "thumbnail": {
    "musicThumbnailRenderer": {
      "thumbnail": {
        "thumbnails": [
          {"url": "https://yt3.ggpht.com/small=w60-h60", "width": 60},
          {"url": "https://yt3.ggpht.com/large=w544-h544", "width": 544}
        ]
      }
    }
  },
  "title": {"runs": [{"text": "Instant Crush (feat. Julian Casablancas)"}]},
  "subtitle": {
    "runs": [
      {"text": "Daft Punk"},
      {"text": " & "},
      {"text": "Julian Casablancas"},
      {"text": " • "},
      {"text": "5:38"},
      {"text": " • "},
      {"text": "1.2B plays"}
    ]
  },
  "navigationEndpoint": {
    "watchEndpoint": {"videoId": "khnokW3Mw24"}
  }
}}]}}]}}}
''';

/// iOS music search: `musicResponsiveListItemRenderer` with flex columns.
const String iosMusicSearchResponse = r'''
{
 "contents": {
  "tabbedSearchResultsRenderer": {
   "tabs": [
    {
     "tabContent": {
      "sectionListRenderer": {
       "contents": [
        {
         "itemSectionRenderer": {
          "contents": [
           {
            "musicShelfRenderer": {
             "contents": [
              {
               "musicResponsiveListItemRenderer": {
                "thumbnail": {
                 "musicThumbnailRenderer": {
                  "thumbnail": {
                   "thumbnails": [
                    {
                     "url": "https://yt3.ggpht.com/ios=w120",
                     "width": 120
                    }
                   ]
                  }
                 }
                },
                "flexColumns": [
                 {
                  "musicResponsiveListItemFlexColumnRenderer": {
                   "text": {
                    "runs": [
                     {
                      "text": "Get Lucky"
                     }
                    ]
                   }
                  }
                 },
                 {
                  "musicResponsiveListItemFlexColumnRenderer": {
                   "text": {
                    "runs": [
                     {
                      "text": "Daft Punk"
                     },
                     {
                      "text": " • "
                     },
                     {
                      "text": "Random Access Memories"
                     },
                     {
                      "text": " • "
                     },
                     {
                      "text": "2013"
                     },
                     {
                      "text": " • "
                     },
                     {
                      "text": "6:09"
                     }
                    ]
                   }
                  }
                 }
                ],
                "fixedColumns": [
                 {
                  "musicResponsiveListItemFixedColumnRenderer": {
                   "text": {
                    "simpleText": "6:09"
                   }
                  }
                 }
                ],
                "navigationEndpoint": {
                 "watchEndpoint": {
                  "videoId": "2Fbl0XOVCmw"
                 }
                },
                "playlistItemData": {
                 "videoId": "2Fbl0XOVCmw"
                }
               }
              }
             ]
            }
           }
          ]
         }
        }
       ]
      }
     }
    }
   ]
  }
 }
}
''';

/// `/player` response with directly playable audio formats.
///
/// itag 140 (129 kbps M4A) must outrank itag 249 (55 kbps Opus) and itag 139
/// (48 kbps M4A); itag 18 is video-only and must be excluded.
const String playablePlayerResponse = r'''
{
  "playabilityStatus": {"status": "OK"},
  "videoDetails": {
    "videoId": "khnokW3Mw24",
    "title": "Instant Crush",
    "author": "Daft Punk",
    "lengthSeconds": "338"
  },
  "streamingData": {
    "expiresInSeconds": "21540",
    "adaptiveFormats": [
      {
        "itag": 139,
        "url": "https://rr3---sn-test.googlevideo.com/videoplayback?itag=139",
        "mimeType": "audio/mp4; codecs=\"mp4a.40.5\"",
        "bitrate": 48847,
        "contentLength": "2061125",
        "audioSampleRate": 22050,
        "audioChannels": 2,
        "audioQuality": "AUDIO_QUALITY_LOW"
      },
      {
        "itag": 249,
        "url": "https://rr3---sn-test.googlevideo.com/videoplayback?itag=249",
        "mimeType": "audio/webm; codecs=\"opus\"",
        "bitrate": 55620,
        "contentLength": "2345678",
        "audioSampleRate": 48000,
        "audioChannels": 2,
        "audioQuality": "AUDIO_QUALITY_MEDIUM"
      },
      {
        "itag": 140,
        "url": "https://rr3---sn-test.googlevideo.com/videoplayback?itag=140",
        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
        "bitrate": 129546,
        "contentLength": "5466181",
        "audioSampleRate": 44100,
        "audioChannels": 2,
        "audioQuality": "AUDIO_QUALITY_MEDIUM"
      }
    ],
    "formats": [
      {
        "itag": 18,
        "url": "https://rr3---sn-test.googlevideo.com/videoplayback?itag=18",
        "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
        "bitrate": 500000
      }
    ]
  }
}
''';

/// Audio formats with neither `url` nor `signatureCipher`, exactly as the
/// tokenless Android client returns: playable, but with nothing to play.
const String urlLessPlayerResponse = r'''
{
  "playabilityStatus": {"status": "OK"},
  "streamingData": {
    "adaptiveFormats": [
      {
        "itag": 140,
        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
        "bitrate": 129546,
        "audioSampleRate": 44100,
        "audioQuality": "AUDIO_QUALITY_MEDIUM"
      }
    ]
  }
}
''';

/// Audio behind a signature cipher, which needs a solver this app lacks.
const String cipheredPlayerResponse = r'''
{
  "playabilityStatus": {"status": "OK"},
  "streamingData": {
    "adaptiveFormats": [
      {
        "itag": 140,
        "signatureCipher": "s=encrypted-value&sp=sig&url=https%3A%2F%2Frr3.googlevideo.com%2Fvideoplayback%3Fitag%3D140",
        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
        "bitrate": 129546,
        "audioSampleRate": 44100,
        "audioQuality": "AUDIO_QUALITY_MEDIUM"
      }
    ]
  }
}
''';

/// DRM-protected audio, which cannot be handed to a decoder.
const String drmPlayerResponse = r'''
{
  "playabilityStatus": {"status": "OK"},
  "streamingData": {
    "adaptiveFormats": [
      {
        "itag": 328,
        "url": "https://rr3---sn-test.googlevideo.com/videoplayback?itag=328",
        "mimeType": "audio/mp4; codecs=\"mp4a.40.5\"",
        "bitrate": 128000,
        "audioSampleRate": 44100,
        "drmFamilies": ["WIDEVINE"]
      }
    ]
  }
}
''';

/// A response reporting the track cannot be played.
const String unplayablePlayerResponse = r'''
{
  "playabilityStatus": {
    "status": "UNPLAYABLE",
    "reason": "Video unavailable"
  },
  "streamingData": {}
}
''';

/// Minimal bootstrap HTML carrying the three scraped values.
const String bootstrapHtml = r'''
<script>var ytcfg = {"INNERTUBE_API_KEY":"AIzaSyTESTKEY",
"INNERTUBE_CLIENT_VERSION":"1.20260928.13.00",
"VISITOR_DATA":"CgtIb3Rlc3Q"};</script>
''';