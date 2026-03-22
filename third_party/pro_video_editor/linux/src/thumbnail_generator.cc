#include "thumbnail_generator.h"

#include <flutter/standard_method_codec.h>

#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <iostream>
#include <chrono>
#include <filesystem>
#include <future>
#include <cstdlib>
#include <iomanip>

namespace fs = std::filesystem;
namespace pro_video_editor {

std::string GenerateTempFilename(const std::string& prefix, const std::string& extension) {
    std::stringstream filename;
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;

    std::tm tm = *std::localtime(&time);
    filename << "/tmp/" << prefix << "_"
             << std::put_time(&tm, "%Y%m%d%H%M%S")
             << ms.count() << extension;

    return filename.str();
}

bool WriteBytesToFile(const std::string& path, const std::vector<uint8_t>& bytes) {
    std::ofstream out(path, std::ios::binary);
    if (!out.is_open()) return false;
    out.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    return true;
}

void HandleGenerateThumbnails(
    const flutter::EncodableMap& args,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const auto* videoBytes = std::get_if<std::vector<uint8_t>>(&args.at(flutter::EncodableValue("videoBytes")));
    const auto* timestampsList = std::get_if<flutter::EncodableList>(&args.at(flutter::EncodableValue("timestamps")));
    const auto* formatStr = std::get_if<std::string>(&args.at(flutter::EncodableValue("thumbnailFormat")));
    const auto* extensionStr = std::get_if<std::string>(&args.at(flutter::EncodableValue("extension")));
    const auto* width = std::get_if<double>(&args.at(flutter::EncodableValue("imageWidth")));

    if (!videoBytes || !timestampsList || !formatStr || !extensionStr || !width) {
        result->Error("InvalidArgument", "Missing required parameters");
        return;
    }

    int roundedWidth = static_cast<int>(std::round(*width));
    std::string videoExt = *extensionStr;
    if (videoExt.empty() || videoExt[0] != '.') videoExt = "." + videoExt;

    std::string imageExt = *formatStr;
    if (imageExt.empty() || imageExt[0] != '.') imageExt = "." + imageExt;

    std::string tempVideoPath = GenerateTempFilename("video_temp", videoExt);
    if (!WriteBytesToFile(tempVideoPath, *videoBytes)) {
        result->Error("FileError", "Failed to write temp video file");
        return;
    }

    // Assume `ffmpeg` is in system PATH on Linux
    std::string ffmpegPath = "ffmpeg";

    std::vector<std::future<void>> futures;
    std::vector<flutter::EncodableValue> thumbnails(timestampsList->size());

    int index = 0;
    for (const auto& tsValue : *timestampsList) {
        if (!std::holds_alternative<int>(tsValue)) {
            ++index;
            continue;
        }

        int currentIndex = index++;
        int64_t tsMs = static_cast<int64_t>(std::get<int>(tsValue));
        double tsSec = tsMs / 1000.0;

        futures.push_back(std::async(std::launch::async, [=, &thumbnails]() {
            std::ostringstream timestampStream;
            timestampStream << std::fixed << std::setprecision(3) << tsSec;

            std::string tempImagePath = GenerateTempFilename("thumb_" + std::to_string(currentIndex), imageExt);

            std::ostringstream cmd;
            cmd << ffmpegPath
                << " -ss " << timestampStream.str()
                << " -i \"" << tempVideoPath << "\""
                << " -vframes 1 -vf scale=" << roundedWidth << ":-2"
                << " \"" << tempImagePath << "\"";

            int retCode = std::system(cmd.str().c_str());

            if (retCode == 0 && fs::exists(tempImagePath)) {
                std::ifstream in(tempImagePath, std::ios::binary);
                std::vector<uint8_t> imageBytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
                thumbnails[currentIndex] = flutter::EncodableValue(imageBytes);
                std::remove(tempImagePath.c_str());
            }
        }));
    }

    for (auto& fut : futures) {
        fut.get();
    }

    std::remove(tempVideoPath.c_str());
    result->Success(thumbnails);
}

} // namespace pro_video_editor
