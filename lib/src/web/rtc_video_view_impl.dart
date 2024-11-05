import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:js_interop';
import 'dart:js_util';

import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:web/web.dart' as web;
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:webrtc_interface/webrtc_interface.dart';

import 'rtc_video_renderer_impl.dart';

class RTCVideoView extends StatefulWidget {
  RTCVideoView(
    this._renderer, {
    super.key,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    this.mirror = false,
    this.filterQuality = FilterQuality.low,
    this.placeholderBuilder,
    this.useHtmlElementView = false,
  }) : super(key: key);

  final bool useHtmlElementView;
  final RTCVideoRenderer _renderer;
  final RTCVideoViewObjectFit objectFit;
  final bool mirror;
  final FilterQuality filterQuality;
  final WidgetBuilder? placeholderBuilder;

  @override
  RTCVideoViewState createState() => RTCVideoViewState();
}

class RTCVideoViewState extends State<RTCVideoView> {
  RTCVideoViewState();

  RTCVideoRenderer get videoRenderer => widget._renderer;

  @override
  void initState() {
    super.initState();
    videoRenderer.addListener(_onRendererListener);
    videoRenderer.mirror = widget.mirror;
    videoRenderer.objectFit =
        widget.objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
            ? 'contain'
            : 'cover';
    frameCallback(0.toJS, 0.toJS);
  }

  void _onRendererListener() {
    if (mounted) setState(() {});
  }

  int? callbackID;

  void getFrame(web.HTMLVideoElement element) {
    callbackID =
        element.requestVideoFrameCallbackWithFallback(frameCallback.toJS);
  }

  void cancelFrame(web.HTMLVideoElement element) {
    if (callbackID != null) {
      element.cancelVideoFrameCallbackWithFallback(callbackID!);
    }
  }

  void frameCallback(JSAny now, JSAny metadata) {
    final web.HTMLVideoElement? element = videoRenderer.videoElement;
    if (element != null) {
      // only capture frames if video is playing (optimization for RAF)
      if (element.readyState > 2) {
        capture().then((_) async {
          getFrame(element);
        });
      } else {
        getFrame(element);
      }
    } else {
      if (mounted) {
        Future.delayed(Duration(milliseconds: 100)).then((_) {
          frameCallback(0.toJS, 0.toJS);
        });
      }
    }
  }

  ui.Image? capturedFrame;
  num? lastFrameTime;
  Future<void> capture() async {
    final element = videoRenderer.videoElement!;
    if (lastFrameTime != element.currentTime) {
      lastFrameTime = element.currentTime;
      try {
        final ui.Image img = await ui_web.createImageFromTextureSource(element,
            width: element.videoWidth,
            height: element.videoHeight,
            transferOwnership: false);

        if (mounted) {
          setState(() {
            capturedFrame?.dispose();
            capturedFrame = img;
          });
        }
      } on web.DOMException catch (err) {
        lastFrameTime = null;
        if (err.name == 'InvalidStateError') {
          // We don't have enough data yet, continue on
        } else {
          rethrow;
        }
      }
    }
  }

  @override
  void dispose() {
    if (mounted) {
      super.dispose();
    }
    if (videoRenderer.videoElement != null) {
      cancelFrame(videoRenderer.videoElement!);
    }
  }

  @override
  void didUpdateWidget(RTCVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    Timer(
        Duration(milliseconds: 10), () => videoRenderer.mirror = widget.mirror);
    videoRenderer.objectFit =
        widget.objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
            ? 'contain'
            : 'cover';
  }

  Widget buildVideoElementView() {
    if (widget.useHtmlElementView) {
      return HtmlElementView.fromTagName(
          tagName: "div",
          onElementCreated: (element) {
            final div = element as web.HTMLDivElement;
            div.style.width = '100%';
            div.style.height = '100%';
            div.appendChild(videoRenderer.videoElement!);
          });
    } else {
      final image = capturedFrame != null
          ? RawImage(
              image: capturedFrame,
              fit: switch (widget.objectFit) {
                RTCVideoViewObjectFit.RTCVideoViewObjectFitContain =>
                  BoxFit.contain,
                RTCVideoViewObjectFit.RTCVideoViewObjectFitCover =>
                  BoxFit.cover,
              })
          : null;
      return Stack(children: [
        Positioned.fill(
            child: HtmlElementView.fromTagName(
                tagName: "div",
                isVisible: false,
                onElementCreated: (element) {
                  final div = element as web.HTMLDivElement;
                  div.style.width = '100%';
                  div.style.height = '100%';
                  div.style.pointerEvents = 'none';
                  div.style.opacity = '0';
                  div.appendChild(videoRenderer.videoElement!);
                })),
        if (capturedFrame != null)
          Positioned.fill(
              child: widget.mirror
                  ? Transform.flip(flipX: true, child: image!)
                  : image!),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Center(
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: widget._renderer.renderVideo
                ? buildVideoElementView()
                : widget.placeholderBuilder?.call(context) ?? Container(),
          ),
        );
      },
    );
  }
}

typedef _VideoFrameRequestCallback = JSFunction;

extension _HTMLVideoElementRequestAnimationFrame on web.HTMLVideoElement {
  int requestVideoFrameCallbackWithFallback(
      _VideoFrameRequestCallback callback) {
    if (hasProperty(this, 'requestVideoFrameCallback')) {
      return requestVideoFrameCallback(callback);
    } else {
      return web.window.requestAnimationFrame((double num) {
        callback.callAsFunction(this, 0.toJS, 0.toJS);
      }.toJS);
    }
  }

  void cancelVideoFrameCallbackWithFallback(int callbackID) {
    if (hasProperty(this, 'requestVideoFrameCallback')) {
      cancelVideoFrameCallback(callbackID);
    } else {
      web.window.cancelAnimationFrame(callbackID);
    }
  }

  external int requestVideoFrameCallback(_VideoFrameRequestCallback callback);
  external void cancelVideoFrameCallback(int callbackID);
}
