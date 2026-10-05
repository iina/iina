"""Contract-level tests for the player-scoped timeline thumbnail API.

These tests exercise the bounded broker/session model independently of AppKit and
JavaScriptCore. They are deliberately separate from live IINA runtime evidence;
the native target still needs the repository's Xcode build to run.
"""
import pathlib
import unittest
from dataclasses import dataclass

MAX_ITEMS = 128
MAX_ITEM_BYTES = 256 * 1024
MAX_UPDATE_BYTES = 8 * 1024 * 1024


@dataclass(frozen=True)
class MediaKey:
    url: str
    size: int
    mtime: float
    track: str


@dataclass(frozen=True)
class Session:
    request_id: str
    media: MediaKey


class BrokerModel:
    def __init__(self):
        self.session = None
        self.state = "unavailable"
        self.progress = 0.0
        self.items = []
        self.listeners = {}
        self.deliveries = []

    def subscribe(self, token):
        self.listeners[token] = True
        self.deliveries.append((token, self.state, list(self.items)))

    def unsubscribe(self, token):
        self.listeners.pop(token, None)

    def begin(self, session):
        self.session = session
        self.state = "generating"
        self.progress = 0.0
        self.items = []
        self._emit()

    def partial(self, session, request_id, items, progress):
        if session != self.session or request_id != session.request_id:
            return False
        self.items.extend(items)
        self.items = self.items[:MAX_ITEMS]
        self.progress = max(0.0, min(1.0, progress))
        self.state = "partial"
        self._emit()
        return True

    def ready(self, session, request_id, items):
        if session != self.session or request_id != session.request_id:
            return False
        self.items = items[:MAX_ITEMS]
        self.progress = 1.0
        self.state = "ready"
        self._emit()
        return True

    def invalidate(self, reason):
        self.session = None
        self.state = "invalidated"
        self.progress = 0.0
        self.items = []
        self._emit(reason)

    def _emit(self, reason=None):
        for token in self.listeners:
            self.deliveries.append((token, self.state, list(self.items), reason))


def bounded_transfer(items):
    accepted = []
    total = 0
    for item in items:
        size = item[1]
        if size <= 0 or size > MAX_ITEM_BYTES:
            continue
        if len(accepted) >= MAX_ITEMS or total + size > MAX_UPDATE_BYTES:
            break
        accepted.append(item)
        total += size
    return accepted, total


class TimelineThumbnailAPIContractTests(unittest.TestCase):
    def setUp(self):
        self.media = MediaKey("file:///movie.mov", 100, 200.0, "vid=1;codec=h264")
        self.session = Session("request-1", self.media)

    def test_cache_hit_and_fresh_generation_have_ready_parity(self):
        fresh = BrokerModel()
        fresh.subscribe("plugin")
        fresh.begin(self.session)
        self.assertTrue(fresh.partial(self.session, "request-1", [(0.0, 100)], 0.5))
        self.assertTrue(fresh.ready(self.session, "request-1", [(0.0, 100), (1.0, 100)]))

        cache = BrokerModel()
        cache.subscribe("plugin")
        cache.begin(self.session)
        self.assertTrue(cache.ready(self.session, "request-1", [(0.0, 100), (1.0, 100)]))

        self.assertEqual(fresh.state, cache.state)
        self.assertEqual(fresh.progress, cache.progress)
        self.assertEqual(fresh.items, cache.items)

    def test_partial_progress_and_final_completion(self):
        broker = BrokerModel()
        broker.subscribe("plugin")
        broker.begin(self.session)
        self.assertTrue(broker.partial(self.session, "request-1", [(0.0, 10)], 0.2))
        self.assertTrue(broker.partial(self.session, "request-1", [(1.0, 10)], 0.8))
        self.assertEqual(broker.state, "partial")
        self.assertEqual(broker.progress, 0.8)
        self.assertTrue(broker.ready(self.session, "request-1", [(0.0, 10), (1.0, 10)]))
        self.assertEqual((broker.state, broker.progress), ("ready", 1.0))

    def test_file_change_invalidates_and_drops_late_result(self):
        broker = BrokerModel()
        broker.begin(self.session)
        broker.invalidate("file-metadata-changed")
        self.assertFalse(broker.ready(self.session, "request-1", [(0.0, 10)]))
        self.assertEqual(broker.state, "invalidated")

    def test_video_track_change_invalidates(self):
        broker = BrokerModel()
        broker.begin(self.session)
        changed = Session("request-2", MediaKey(self.media.url, self.media.size, self.media.mtime, "vid=2;codec=h264"))
        broker.invalidate("video-track-changed")
        broker.begin(changed)
        self.assertFalse(broker.partial(self.session, "request-1", [(9.0, 10)], 0.9))
        self.assertEqual(broker.session, changed)

    def test_stale_request_id_is_rejected_even_for_same_file(self):
        broker = BrokerModel()
        broker.begin(self.session)
        newer = Session("request-2", self.media)
        broker.begin(newer)
        self.assertFalse(broker.partial(newer, "request-1", [(9.0, 10)], 0.9))
        self.assertEqual(broker.items, [])

    def test_unsubscribe_and_plugin_unload_stop_delivery(self):
        broker = BrokerModel()
        broker.subscribe("plugin")
        broker.begin(self.session)
        broker.unsubscribe("plugin")
        before = len(broker.deliveries)
        broker.ready(self.session, "request-1", [(0.0, 10)])
        self.assertEqual(len(broker.deliveries), before)

    def test_malformed_and_oversized_data_are_dropped(self):
        accepted, total = bounded_transfer([(0.0, 0), (1.0, MAX_ITEM_BYTES + 1), (2.0, 64)])
        self.assertEqual(accepted, [(2.0, 64)])
        self.assertEqual(total, 64)

    def test_count_and_total_byte_limits(self):
        accepted, total = bounded_transfer([(float(i), 64 * 1024) for i in range(200)])
        self.assertLessEqual(len(accepted), MAX_ITEMS)
        self.assertLessEqual(total, MAX_UPDATE_BYTES)

    def test_backward_compatibility_keeps_existing_api_registration(self):
        root = pathlib.Path(__file__).parents[3]
        source = (root / "iina" / "JavascriptPluginInstance.swift").read_text()
        self.assertIn('apis["core"]', source)
        self.assertIn('apis["mpv"]', source)
        self.assertIn('apis["event"]', source)
        self.assertIn('apis["thumbnails"]', source)

    def test_native_generation_wires_request_ids_and_cache_ready_event(self):
        root = pathlib.Path(__file__).parents[3]
        ffmpeg = (root / "iina" / "FFmpegController.m").read_text()
        player = (root / "iina" / "PlayerCore.swift").read_text()
        track = (root / "iina" / "MPVTrack.swift").read_text()
        javascript = (root / "iina" / "JavascriptAPIThumbnails.swift").read_text()
        self.assertIn("requestID:(NSString *)requestID", ffmpeg)
        self.assertIn("requestID:requestID", ffmpeg)
        self.assertIn("operation.isCancelled", ffmpeg)
        self.assertIn('(dict["ff-index"] as? Int64).map', track)
        self.assertIn("JSObjectIsFunction", javascript)
        self.assertIn("ffmpegControllerWasInitialized", player)
        self.assertIn('"codec=\\($0.codec ?? "nil")"', player)
        self.assertIn('"fps=\\($0.frameRate.map { String($0) } ?? "nil")"', player)
        self.assertIn("session.cacheName", player)
        self.assertIn("self.events.emit(.thumbnailsReady)", player)
        self.assertIn("timelineThumbnailBroker.publishReady(thumbnails, for: session)", player)


if __name__ == "__main__":
    unittest.main()
