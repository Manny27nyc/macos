/*
 *  Copyright (C) 2017-2022 Igalia S.L. All rights reserved.
 *  Copyright (C) 2022 Metrological Group B.V.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include "config.h"

#if USE(GSTREAMER_WEBRTC)
#include "RealtimeIncomingSourceGStreamer.h"

#include <gst/app/gstappsink.h>
#include <wtf/text/WTFString.h>

GST_DEBUG_CATEGORY_EXTERN(webkit_webrtc_endpoint_debug);
#define GST_CAT_DEFAULT webkit_webrtc_endpoint_debug

namespace WebCore {

RealtimeIncomingSourceGStreamer::RealtimeIncomingSourceGStreamer(const CaptureDevice& device)
    : RealtimeMediaSource(device)
{
    m_bin = gst_bin_new(nullptr);
    m_valve = gst_element_factory_make("valve", nullptr);
    m_tee = gst_element_factory_make("tee", nullptr);
    g_object_set(m_tee.get(), "allow-not-linked", true, nullptr);

    auto* queue = gst_element_factory_make("queue", nullptr);
    gst_bin_add_many(GST_BIN_CAST(m_bin.get()), m_valve.get(), queue, m_tee.get(), nullptr);

    gst_element_link_many(m_valve.get(), queue, m_tee.get(), nullptr);
    gst_element_sync_state_with_parent(m_valve.get());
    gst_element_sync_state_with_parent(queue);
    gst_element_sync_state_with_parent(m_tee.get());

    auto sinkPad = adoptGRef(gst_element_get_static_pad(m_valve.get(), "sink"));
    gst_element_add_pad(m_bin.get(), gst_ghost_pad_new("sink", sinkPad.get()));
}

void RealtimeIncomingSourceGStreamer::startProducingData()
{
    GST_DEBUG_OBJECT(bin(), "Starting data flow");
    openValve();
}

void RealtimeIncomingSourceGStreamer::stopProducingData()
{
    GST_DEBUG_OBJECT(bin(), "Stopping data flow");
    closeValve();
}

const RealtimeMediaSourceCapabilities& RealtimeIncomingSourceGStreamer::capabilities()
{
    return RealtimeMediaSourceCapabilities::emptyCapabilities();
}

void RealtimeIncomingSourceGStreamer::closeValve() const
{
    if (m_valve)
        g_object_set(m_valve.get(), "drop", true, nullptr);
}

void RealtimeIncomingSourceGStreamer::openValve() const
{
    if (m_valve)
        g_object_set(m_valve.get(), "drop", false, nullptr);
}

void RealtimeIncomingSourceGStreamer::registerClient()
{
    GST_DEBUG("Registering new client");
    auto* queue = gst_element_factory_make("queue", nullptr);
    auto* sink = gst_element_factory_make("appsink", nullptr);
    g_object_set(sink, "enable-last-sample", FALSE, "emit-signals", TRUE, "max-buffers", 1, nullptr);
    g_signal_connect_swapped(sink, "new-sample", G_CALLBACK(+[](RealtimeIncomingSourceGStreamer* self, GstElement* sink) -> GstFlowReturn {
        auto sample = adoptGRef(gst_app_sink_pull_sample(GST_APP_SINK(sink)));
        self->dispatchSample(WTFMove(sample));
        return GST_FLOW_OK;
    }), this);

    g_signal_connect_swapped(sink, "new-preroll", G_CALLBACK(+[](RealtimeIncomingSourceGStreamer* self, GstElement* sink) -> GstFlowReturn {
        auto sample = adoptGRef(gst_app_sink_pull_preroll(GST_APP_SINK(sink)));
        self->dispatchSample(WTFMove(sample));
        return GST_FLOW_OK;
    }), this);

    g_signal_connect_swapped(sink, "new-serialized-event", G_CALLBACK(+[](RealtimeIncomingSourceGStreamer* self, GstElement* sink) -> gboolean {
        auto event = adoptGRef(GST_EVENT_CAST(gst_app_sink_pull_object(GST_APP_SINK(sink))));
        switch (GST_EVENT_TYPE(event.get())) {
        case GST_EVENT_STREAM_START:
        case GST_EVENT_CAPS:
            return false;
        default:
            break;
        }
        self->handleDownstreamEvent(WTFMove(event));
        return true;
    }), this);

    gst_bin_add_many(GST_BIN_CAST(m_bin.get()), queue, sink, nullptr);
    gst_element_link_many(m_tee.get(), queue, sink, nullptr);
    gst_element_sync_state_with_parent(queue);
    gst_element_sync_state_with_parent(sink);

#ifndef GST_DISABLE_GST_DEBUG
    auto dotFileName = makeString(GST_OBJECT_NAME(m_bin.get()), ".incoming");
    GST_DEBUG_BIN_TO_DOT_FILE_WITH_TS(GST_BIN_CAST(m_bin.get()), GST_DEBUG_GRAPH_SHOW_ALL, dotFileName.utf8().data());
#endif
}

void RealtimeIncomingSourceGStreamer::handleUpstreamEvent(GRefPtr<GstEvent>&& event)
{
    GST_DEBUG_OBJECT(m_bin.get(), "Handling %" GST_PTR_FORMAT, event.get());
    auto pad = adoptGRef(gst_element_get_static_pad(m_tee.get(), "sink"));
    gst_pad_push_event(pad.get(), event.leakRef());
}

void RealtimeIncomingSourceGStreamer::handleDownstreamEvent(GRefPtr<GstEvent>&& event)
{
    GST_DEBUG_OBJECT(bin(), "Handling %" GST_PTR_FORMAT, event.get());
    forEachObserver([event = WTFMove(event)](Observer& observer) {
        observer.handleDownstreamEvent(GRefPtr<GstEvent>(event.get()));
    });
}

} // namespace WebCore

#endif // USE(GSTREAMER_WEBRTC)
