#include "video_metadata.h"

#include <flutter/standard_method_codec.h>
#include <gst/gst.h>
#include <gst/pbutils/pbutils.h>
#include <fstream>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string>
#include <vector>
#include <map>
#include <ctime>

namespace pro_video_editor {

void HandleGetMetadata(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    auto itPath = args.find(flutter::EncodableValue("inputPath"));
    if (itPath == args.end()) {
        result->Error("InvalidArgument", "Missing inputPath");
        return;
    }
    const auto* pathStr = std::get_if<std::string>(&itPath->second);
    if (!pathStr) {
        result->Error("InvalidArgument", "Invalid inputPath format");
        return;
    }

    std::string inputPath = *pathStr;

    struct stat file_stat;
    int64_t fileSize = 0;
    std::string dateStr;
    if (stat(inputPath.c_str(), &file_stat) == 0) {
        fileSize = file_stat.st_size;

        char buffer[64];
        std::tm* tm = std::localtime(&file_stat.st_ctime);
        std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", tm);
        dateStr = buffer;
    } else {
        result->Error("FileError", "Failed to stat file");
        return;
    }

    gst_init(nullptr, nullptr);

    GstDiscoverer* discoverer = gst_discoverer_new(5 * GST_SECOND, nullptr);
    if (!discoverer) {
        result->Error("GStreamerError", "Failed to create discoverer");
        return;
    }

    std::string uri = "file://" + inputPath;
    GstDiscovererInfo* info = gst_discoverer_discover_uri(discoverer, uri.c_str(), nullptr);

    if (!info) {
        g_object_unref(discoverer);
        result->Error("GStreamerError", "Failed to get metadata");
        return;
    }

    const GstDiscovererStreamInfo* streamInfo = gst_discoverer_info_get_stream_info(info);
    const GstCaps* caps = gst_discoverer_stream_info_get_caps(streamInfo);

    int width = 0, height = 0, rotation = 0;
    double duration_ms = 0.0;
    int bitrate = 0;

    if (caps) {
        const GstStructure* s = gst_caps_get_structure(caps, 0);
        gst_structure_get_int(s, "width", &width);
        gst_structure_get_int(s, "height", &height);
    }

    gint64 duration_ns = gst_discoverer_info_get_duration(info);
    duration_ms = static_cast<double>(duration_ns) / GST_MSECOND;

    if (duration_ms > 0.0) {
        bitrate = static_cast<int>((fileSize * 8) / (duration_ms / 1000.0));
    }

    const GstTagList* tags = gst_discoverer_info_get_tags(info);
    gchar* title = nullptr;
    if (tags) {
        gst_tag_list_get_string(tags, GST_TAG_TITLE, &title);
    }

    flutter::EncodableMap result_map;
    result_map[flutter::EncodableValue("fileSize")] = flutter::EncodableValue(static_cast<int64_t>(fileSize));
    result_map[flutter::EncodableValue("duration")] = flutter::EncodableValue(duration_ms);
    result_map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
    result_map[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
    result_map[flutter::EncodableValue("rotation")] = flutter::EncodableValue(rotation);  // Rotation not available via GStreamer tags directly
    result_map[flutter::EncodableValue("bitrate")] = flutter::EncodableValue(bitrate);
    result_map[flutter::EncodableValue("title")] = flutter::EncodableValue(title ? title : "");
    result_map[flutter::EncodableValue("artist")] = flutter::EncodableValue("");
    result_map[flutter::EncodableValue("author")] = flutter::EncodableValue("");
    result_map[flutter::EncodableValue("album")] = flutter::EncodableValue("");
    result_map[flutter::EncodableValue("albumArtist")] = flutter::EncodableValue("");
    result_map[flutter::EncodableValue("date")] = flutter::EncodableValue(dateStr);

    if (title) g_free(title);
    gst_discoverer_info_unref(info);
    g_object_unref(discoverer);

    result->Success(flutter::EncodableValue(result_map));
}

}  // namespace pro_video_editor
