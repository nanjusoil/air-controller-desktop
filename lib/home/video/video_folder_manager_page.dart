import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flowder/flowder.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_assistant_client/event/back_btn_pressed.dart';
import 'package:mobile_assistant_client/event/back_btn_visibility.dart';
import 'package:mobile_assistant_client/event/delete_op.dart';
import 'package:mobile_assistant_client/event/update_bottom_item_num.dart';
import 'package:mobile_assistant_client/event/update_delete_btn_status.dart';
import 'package:mobile_assistant_client/event/update_video_sort_order.dart';
import 'package:mobile_assistant_client/event/video_sort_menu_visibility.dart';
import 'package:mobile_assistant_client/model/UIModule.dart';
import 'package:mobile_assistant_client/model/video_folder_item.dart';
import 'package:mobile_assistant_client/model/video_item.dart';
import 'package:mobile_assistant_client/network/device_connection_manager.dart';
import 'package:mobile_assistant_client/util/event_bus.dart';
import 'package:mobile_assistant_client/widget/confirm_dialog_builder.dart';
import 'package:mobile_assistant_client/widget/progress_indictor_dialog.dart';
import 'package:mobile_assistant_client/widget/video_flow_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../constant.dart';
import '../../model/ResponseEntity.dart';
import '../video_manager_page.dart';

class VideoFolderManagerPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _VideoFolderManagerState();
  }
}

class _VideoFolderManagerState extends State<VideoFolderManagerPage> with AutomaticKeepAliveClientMixin {
  bool _isLoadingCompleted = true;

  final _BACKGROUND_ALBUM_SELECTED = Color(0xffe6e6e6);
  final _BACKGROUND_ALBUM_NORMAL = Colors.white;

  final _ALBUM_NAME_TEXT_COLOR_NORMAL = Color(0xff515151);
  final _ALBUM_IMAGE_NUM_TEXT_COLOR_NORMAL = Color(0xff929292);

  final _ALBUM_NAME_TEXT_COLOR_SELECTED = Colors.white;
  final _ALBUM_IMAGE_NUM_TEXT_COLOR_SELECTED = Colors.white;

  final _BACKGROUND_ALBUM_NAME_NORMAL = Colors.white;
  final _BACKGROUND_ALBUM_NAME_SELECTED = Color(0xff5d87ed);

  final _OUT_PADDING = 20.0;
  final _IMAGE_SPACE = 15.0;

  final _KB_BOUND = 1 * 1024;
  final _MB_BOUND = 1 * 1024 * 1024;
  final _GB_BOUND = 1 * 1024 * 1024 * 1024;

  List<VideoFolderItem> _selectedVideoFolders = [];
  List<VideoFolderItem> _videoFolders = [];

  final _URL_SERVER = "http://${DeviceConnectionManager.instance.currentDevice
      ?.ip}:${Constant.PORT_HTTP}";

  bool _isFolderPageVisible = false;
  bool _isVideosInFolderPageVisible = false;
  int _currentSortOrder = VideoFlowWidget.SORT_ORDER_CREATE_TIME;
  bool _openVideosInFolderPage = false;

  List<VideoItem> _videosInFolder = [];
  List<VideoItem> _selectedVideosInFolder = [];
  VideoFolderItem? _currentVideoFolder;

  bool _isLoadingVideosInFolderCompleted = false;

  StreamSubscription<BackBtnPressed>? _backBtnPressedStream;
  StreamSubscription<DeleteOp>? _deleteOpSubscription;
  StreamSubscription<UpdateVideoSortOrder>? _updateVideoSortOrderStream;

  DownloaderCore? _downloaderCore;
  ProgressIndicatorDialog? _progressIndicatorDialog;

  FocusNode? _rootFocus1;
  FocusNode? _rootFocus2;

  bool _isControlPressed = false;
  bool _isShiftPressed = false;

  @override
  void initState() {
    super.initState();

    _registerEventBus();

    _getAllVideosFolder((videos) {
      setState(() {
        _videoFolders = videos;
      });
    }, (error) {
      debugPrint("_getAllVideosFolder, error: $error");
    });
  }

  void _setAllSelected() {
    if (_isFolderPageVisible) {
      setState(() {
        _selectedVideoFolders.clear();
        _selectedVideoFolders.addAll(_videoFolders);
        updateBottomItemNum();
        _setDeleteBtnEnabled(true);
      });
    }

    if (_isVideosInFolderPageVisible) {
      setState(() {
        _selectedVideosInFolder.clear();
        _selectedVideosInFolder.addAll(_videosInFolder);
        updateBottomItemNum();
        _setDeleteBtnEnabled(true);
      });
    }
  }

  void _registerEventBus() {
    _backBtnPressedStream = eventBus.on<BackBtnPressed>().listen((event) {
      _backVideoFoldersPage();
    });

    _deleteOpSubscription = eventBus.on<DeleteOp>().listen((event) {
      if (event.module == UIModule.Video) {
        if (_isFolderPageVisible) {
          if (_selectedVideoFolders.length <= 0) {
            debugPrint("Warning: selectedVideos is empty!!!");
          } else {
            _tryToDeleteVideoFolders(_selectedVideoFolders);
          }
        }

        if (_isVideosInFolderPageVisible) {
          if (_selectedVideosInFolder.length <= 0) {
            debugPrint("Warning: selectedVideos is empty!!!");
          } else {
            _tryToDeleteVideos(_selectedVideosInFolder);
          }
        }
      }
    });

    _updateVideoSortOrderStream =
        eventBus.on<UpdateVideoSortOrder>().listen((event) {
          if (event.type == UpdateVideoSortOrder.TYPE_CREATE_TIME) {
            setState(() {
              _currentSortOrder = VideoManagerState.SORT_ORDER_CREATE_TIME;
            });
          } else {
            setState(() {
              _currentSortOrder = VideoManagerState.SORT_ORDER_SIZE;
            });
          }
          _reSortVideos();
        });
  }

  void _reSortVideos() {
    var sortedVideos = _videosInFolder;

    if (_currentSortOrder == VideoManagerState.SORT_ORDER_CREATE_TIME) {
      sortedVideos.sort((a, b) {
        return b.createTime - a.createTime;
      });
    } else {
      sortedVideos.sort((a, b) {
        return b.duration - a.duration;
      });
    }

    setState(() {
      _videosInFolder = sortedVideos;
    });
  }

  void _unRegisterEventBus() {
    _backBtnPressedStream?.cancel();
    _deleteOpSubscription?.cancel();
    _deleteOpSubscription?.cancel();
  }

  bool _isControlDown() {
    return _isControlPressed;
  }

  bool _isShiftDown() {
    return _isShiftPressed;
  }

  void _setBackBtnVisible(bool visible) {
    eventBus.fire(BackBtnVisibility(visible));
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xff85a8d0);
    const spinKit = SpinKitCircle(color: color, size: 60.0);

    Widget content = _createGridContent();

    Widget videosInFolderWidget = _createVideosWidget();

    _rootFocus1 = FocusNode();
    _rootFocus1?.canRequestFocus = true;
    _rootFocus1?.requestFocus();

    _rootFocus2 = FocusNode();
    _rootFocus2?.canRequestFocus = true;

    return Stack(
      children: [
        // 视频文件夹页面
        VisibilityDetector(
            key: Key("video_folder_manager"),
            child: Focus(
              autofocus: true,
              focusNode: _rootFocus1,
              child: GestureDetector(
                child: Visibility(
                  child: Stack(children: [
                    content,
                    Visibility(
                      child: Container(child: spinKit, color: Colors.white),
                      maintainSize: false,
                      visible: !_isLoadingCompleted,
                    )
                  ],
                    fit: StackFit.expand,
                  ),
                  visible: !_openVideosInFolderPage,
                ),
                onTap: () {
                  _clearSelectedVideos();
                },
              ),
              onFocusChange: (value) {

              },
              onKey: (node, event) {
                debugPrint(
                    "Outside key pressed: ${event.logicalKey.keyId}, ${event
                        .logicalKey.keyLabel}");

                _isControlPressed =
                Platform.isMacOS ? event.isMetaPressed : event.isControlPressed;
                _isShiftPressed = event.isShiftPressed;

                if (Platform.isMacOS) {
                  if (event.isMetaPressed &&
                      event.isKeyPressed(LogicalKeyboardKey.keyA)) {
                    _onControlAndAPressed();
                    return KeyEventResult.handled;
                  }
                } else {
                  if (event.isControlPressed &&
                      event.isKeyPressed(LogicalKeyboardKey.keyA)) {
                    _onControlAndAPressed();
                    return KeyEventResult.handled;
                  }
                }

                return KeyEventResult.ignored;
              },
            ),
            onVisibilityChanged: (info) {
              setState(() {
                _isFolderPageVisible = info.visibleFraction * 100 >= 100;
                if (_isFolderPageVisible) {
                  updateBottomItemNum();
                  _setDeleteBtnEnabled(_selectedVideoFolders.length > 0);
                  _setSortMenuVisible(false);
                  _setBackBtnVisible(false);
                  _rootFocus1?.requestFocus();
                }
              });
            }),

        // 文件夹内视频页面
        VisibilityDetector(
            key: Key("videos_in_folder"),
            child: Focus(
              autofocus: true,
              focusNode: _rootFocus2,
              child: Visibility(
                child: Column(
                  children: [
                    Container(
                      child: Row(
                        children: [
                          GestureDetector(
                            child: Container(
                              child: Text("视频文件夹", style: TextStyle(
                                  color: Color(0xff5b5c62),
                                  fontSize: 14
                              )),
                              padding: EdgeInsets.only(left: 10),
                            ),
                            onTap: () {
                              _backVideoFoldersPage();
                            },
                          ),

                          Image.asset("icons/ic_right_arrow.png", height: 20),
                          Text(
                              _currentVideoFolder?.name ?? "", style: TextStyle(
                              color: Color(0xff5b5c62),
                              fontSize: 14
                          ))
                        ],
                      ),
                      color: Color(0xfffafafa),
                      height: 30,
                    ),

                    Divider(
                        color: Color(0xffe0e0e0), height: 1.0, thickness: 1.0),

                    Expanded(child: Stack(children: [
                      videosInFolderWidget,
                      Visibility(
                        child: Container(child: spinKit, color: Colors.white),
                        maintainSize: false,
                        visible: !_isLoadingVideosInFolderCompleted,
                      )
                    ],
                      fit: StackFit.expand,
                    ))
                  ],
                ),
                visible: _openVideosInFolderPage,
              ),
              onFocusChange: (value) {

              },
              onKey: (node, event) {
                debugPrint(
                    "Outside key pressed: ${event.logicalKey.keyId}, ${event
                        .logicalKey.keyLabel}");

                _isControlPressed =
                Platform.isMacOS ? event.isMetaPressed : event.isControlPressed;
                _isShiftPressed = event.isShiftPressed;

                if (Platform.isMacOS) {
                  if (event.isMetaPressed &&
                      event.isKeyPressed(LogicalKeyboardKey.keyA)) {
                    _onControlAndAPressed();
                    return KeyEventResult.handled;
                  }
                } else {
                  if (event.isControlPressed &&
                      event.isKeyPressed(LogicalKeyboardKey.keyA)) {
                    _onControlAndAPressed();
                    return KeyEventResult.handled;
                  }
                }

                return KeyEventResult.ignored;
              },
            ),
            onVisibilityChanged: (info) {
              setState(() {
                _isVideosInFolderPageVisible = info.visibleFraction >= 1.0;

                if (_isVideosInFolderPageVisible) {
                  updateBottomItemNum();
                  _setDeleteBtnEnabled(_selectedVideosInFolder.length > 0);
                  _setSortMenuVisible(true);
                  _setBackBtnVisible(true);
                  _rootFocus2?.requestFocus();
                }
              });
            })
      ],
    );
  }

  void _onControlAndAPressed() {
    debugPrint("_onControlAndAPressed.");
    _setAllSelected();
  }

  void _setSortMenuVisible(bool visible) {
    eventBus.fire(VideoSortMenuVisibility(visible));
  }

  void _setVideoFolderSelected(VideoFolderItem videoFolder) {
    debugPrint("Shift key down status: ${_isShiftDown()}");
    debugPrint("Control key down status: ${_isControlDown()}");

    if (!_isContainsVideoFolder(_selectedVideoFolders, videoFolder)) {
      if (_isControlDown()) {
        setState(() {
          _selectedVideoFolders.add(videoFolder);
        });
      } else if (_isShiftDown()) {
        if (_selectedVideoFolders.length == 0) {
          setState(() {
            _selectedVideoFolders.add(videoFolder);
          });
        } else if (_selectedVideoFolders.length == 1) {
          int index = _videoFolders.indexOf(_selectedVideoFolders[0]);

          int current = _videoFolders.indexOf(videoFolder);

          if (current > index) {
            setState(() {
              _selectedVideoFolders = _videoFolders.sublist(index, current + 1);
            });
          } else {
            setState(() {
              _selectedVideoFolders = _videoFolders.sublist(current, index + 1);
            });
          }
        } else {
          int maxIndex = 0;
          int minIndex = 0;

          for (int i = 0; i < _selectedVideoFolders.length; i++) {
            VideoFolderItem current = _selectedVideoFolders[i];
            int index = _videoFolders.indexOf(current);
            if (index < 0) {
              debugPrint("Error image");
              continue;
            }

            if (index > maxIndex) {
              maxIndex = index;
            }

            if (index < minIndex) {
              minIndex = index;
            }
          }

          debugPrint("minIndex: $minIndex, maxIndex: $maxIndex");

          int current = _videoFolders.indexOf(videoFolder);

          if (current >= minIndex && current <= maxIndex) {
            setState(() {
              _selectedVideoFolders =
                  _videoFolders.sublist(current, maxIndex + 1);
            });
          } else if (current < minIndex) {
            setState(() {
              _selectedVideoFolders =
                  _videoFolders.sublist(current, maxIndex + 1);
            });
          } else if (current > maxIndex) {
            setState(() {
              _selectedVideoFolders =
                  _videoFolders.sublist(minIndex, current + 1);
            });
          }
        }
      } else {
        setState(() {
          _selectedVideoFolders.clear();
          _selectedVideoFolders.add(videoFolder);
        });
      }
    } else {
      debugPrint("It's already contains this image, id: ${videoFolder.id}");

      if (_isControlDown()) {
        setState(() {
          _selectedVideoFolders.remove(videoFolder);
        });
      } else if (_isShiftDown()) {
        setState(() {
          _selectedVideoFolders.remove(videoFolder);
        });
      } else {
        setState(() {
          _selectedVideoFolders.clear();
          _selectedVideoFolders.add(videoFolder);
        });
      }
    }

    _setDeleteBtnEnabled(_selectedVideoFolders.length > 0);
    updateBottomItemNum();
  }

  bool _isContainsVideo(List<VideoItem> images, VideoItem current) {
    for (VideoItem imageItem in images) {
      if (imageItem.id == current.id) return true;
    }

    return false;
  }

  void _setVideoSelected(VideoItem video) {
    debugPrint("Shift key down status: ${_isShiftDown()}");
    debugPrint("Control key down status: ${_isControlDown()}");

    if (!_isContainsVideo(_selectedVideosInFolder, video)) {
      if (_isControlDown()) {
        setState(() {
          _selectedVideosInFolder.add(video);
        });
      } else if (_isShiftDown()) {
        if (_selectedVideosInFolder.length == 0) {
          setState(() {
            _selectedVideosInFolder.add(video);
          });
        } else if (_selectedVideosInFolder.length == 1) {
          int index = _videosInFolder.indexOf(_selectedVideosInFolder[0]);

          int current = _videosInFolder.indexOf(video);

          if (current > index) {
            setState(() {
              _selectedVideosInFolder =
                  _videosInFolder.sublist(index, current + 1);
            });
          } else {
            setState(() {
              _selectedVideosInFolder =
                  _videosInFolder.sublist(current, index + 1);
            });
          }
        } else {
          int maxIndex = 0;
          int minIndex = 0;

          for (int i = 0; i < _selectedVideosInFolder.length; i++) {
            VideoItem current = _selectedVideosInFolder[i];
            int index = _videosInFolder.indexOf(current);
            if (index < 0) {
              debugPrint("Error image");
              continue;
            }

            if (index > maxIndex) {
              maxIndex = index;
            }

            if (index < minIndex) {
              minIndex = index;
            }
          }

          debugPrint("minIndex: $minIndex, maxIndex: $maxIndex");

          int current = _videosInFolder.indexOf(video);

          if (current >= minIndex && current <= maxIndex) {
            setState(() {
              _selectedVideosInFolder =
                  _videosInFolder.sublist(current, maxIndex + 1);
            });
          } else if (current < minIndex) {
            setState(() {
              _selectedVideosInFolder =
                  _videosInFolder.sublist(current, maxIndex + 1);
            });
          } else if (current > maxIndex) {
            setState(() {
              _selectedVideosInFolder =
                  _videosInFolder.sublist(minIndex, current + 1);
            });
          }
        }
      } else {
        setState(() {
          _selectedVideosInFolder.clear();
          _selectedVideosInFolder.add(video);
        });
      }
    } else {
      debugPrint("It's already contains this video, id: ${video.id}");

      if (_isControlDown()) {
        setState(() {
          _selectedVideosInFolder.remove(video);
        });
      } else if (_isShiftDown()) {
        setState(() {
          _selectedVideosInFolder.remove(video);
        });
      } else {
        setState(() {
          _selectedVideosInFolder.clear();
          _selectedVideosInFolder.add(video);
        });
      }
    }

    _setDeleteBtnEnabled(_selectedVideosInFolder.length > 0);
    updateBottomItemNum();
  }


  void _clearSelectedVideos() {
    setState(() {
      _selectedVideoFolders.clear();
      updateBottomItemNum();
      _setDeleteBtnEnabled(false);
    });
  }

  void updateBottomItemNum() {
    if (_isFolderPageVisible) {
      eventBus.fire(UpdateBottomItemNum(
          _videoFolders.length, _selectedVideoFolders.length));
    }

    if (_openVideosInFolderPage) {
      eventBus.fire(UpdateBottomItemNum(
          _videosInFolder.length, _selectedVideosInFolder.length));
    }
  }

  void _setDeleteBtnEnabled(bool enable) {
    eventBus.fire(UpdateDeleteBtnStatus(enable));
  }

  void updateDeleteBtnStatus() {
    _setDeleteBtnEnabled(_selectedVideoFolders.length > 0);
  }

  Widget _createGridContent() {
    final imageWidth = 140.0;
    final imageHeight = 140.0;
    final imagePadding = 3.0;

    return Container(
      child: GridView.builder(
        scrollDirection: Axis.vertical,
        physics: ScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            crossAxisSpacing: _IMAGE_SPACE,
            childAspectRatio: 1.0,
            mainAxisSpacing: _IMAGE_SPACE),
        controller: ScrollController(keepScrollOffset: true),
        itemBuilder: (BuildContext context, int index) {
          VideoFolderItem videoFolder = _videoFolders[index];

          return Listener(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  child: Container(
                    child: Stack(
                      children: [
                        Visibility(
                          child: RotationTransition(
                              turns: AlwaysStoppedAnimation(5 / 360),
                              child: Container(
                                width: imageWidth,
                                height: imageHeight,
                                padding: EdgeInsets.all(imagePadding),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                        color: Color(0xffdddddd), width: 1.0),
                                    borderRadius:
                                    BorderRadius.all(Radius.circular(3.0))),
                              )),
                          visible: videoFolder.videoCount > 1 ? true : false,
                        ),
                        Visibility(
                          child: RotationTransition(
                              turns: AlwaysStoppedAnimation(-5 / 360),
                              child: Container(
                                width: imageWidth,
                                height: imageHeight,
                                padding: EdgeInsets.all(imagePadding),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                        color: Color(0xffdddddd), width: 1.0),
                                    borderRadius:
                                    BorderRadius.all(Radius.circular(3.0))),
                              )),
                          visible: videoFolder.videoCount > 2 ? true : false,
                        ),
                        Container(
                          child: CachedNetworkImage(
                              imageUrl:
                              "${_URL_SERVER}/stream/video/thumbnail/${videoFolder
                                  .coverVideoId}/400/400"
                                  .replaceAll("storage/emulated/0/", ""),
                              fit: BoxFit.cover,
                              width: imageWidth,
                              height: imageWidth,
                              memCacheWidth: 400,
                              fadeOutDuration: Duration.zero,
                              fadeInDuration: Duration.zero),
                          padding: EdgeInsets.all(imagePadding),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                  color: Color(0xffdddddd), width: 1.0),
                              borderRadius:
                              BorderRadius.all(Radius.circular(3.0))),
                        )
                      ],
                    ),
                    decoration: BoxDecoration(
                        color: _isContainsVideoFolder(
                            _selectedVideoFolders, videoFolder)
                            ? _BACKGROUND_ALBUM_SELECTED
                            : _BACKGROUND_ALBUM_NORMAL,
                        borderRadius: BorderRadius.all(Radius.circular(4.0))),
                    padding: EdgeInsets.all(8),
                  ),
                  onTap: () {
                    setState(() {
                      _setVideoFolderSelected(videoFolder);
                    });
                  },
                  onDoubleTap: () {
                    _currentVideoFolder = videoFolder;
                    _tryToOpenVideosInFolderPage(videoFolder);
                  },
                ),
                GestureDetector(
                  child: Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          videoFolder.name,
                          style: TextStyle(
                              color: _isContainsVideoFolder(
                                  _selectedVideoFolders, videoFolder)
                                  ? _ALBUM_NAME_TEXT_COLOR_SELECTED
                                  : _ALBUM_NAME_TEXT_COLOR_NORMAL),
                        ),
                        Container(
                          child: Text(
                            "(${videoFolder.videoCount})",
                            style: TextStyle(
                                color: _isContainsVideoFolder(
                                    _selectedVideoFolders, videoFolder)
                                    ? _ALBUM_IMAGE_NUM_TEXT_COLOR_SELECTED
                                    : _ALBUM_IMAGE_NUM_TEXT_COLOR_NORMAL),
                          ),
                          margin: EdgeInsets.only(left: 3),
                        )
                      ],
                    ),
                    margin: EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                        color: _isContainsVideoFolder(
                            _selectedVideoFolders, videoFolder)
                            ? _BACKGROUND_ALBUM_NAME_SELECTED
                            : _BACKGROUND_ALBUM_NAME_NORMAL),
                    padding: EdgeInsets.fromLTRB(10, 5, 10, 5),
                  ),
                  onTap: () {
                    setState(() {
                      // _setAlbumSelected(album);
                    });
                  },
                )
              ],
            ),
            onPointerDown: (event) {
              if (_isMouseRightClicked(event)) {
                if (!_selectedVideoFolders.contains(videoFolder)) {
                  _setVideoFolderSelected(videoFolder);
                }

                _showMenu(event.position, videoFolder);
              }
            },
          );
        },
        itemCount: _videoFolders.length,
        shrinkWrap: true,
        primary: false,
      ),
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(_OUT_PADDING, _OUT_PADDING, _OUT_PADDING, 0),
    );
  }

  bool _isContainsVideoFolder(List<VideoFolderItem> folders,
      VideoFolderItem current) {
    for (VideoFolderItem folder in folders) {
      if (folder.id == current.id) return true;
    }

    return false;
  }

  void _getAllVideosFolder(Function(List<VideoFolderItem> videos) onSuccess,
      Function(String error) onError) {
    var url = Uri.parse("${_URL_SERVER}/video/folders");
    http.post(url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({}))
        .then((response) {
      if (response.statusCode != 200) {
        onError.call(response.reasonPhrase != null
            ? response.reasonPhrase!
            : "Unknown error");
      } else {
        var body = response.body;
        debugPrint("Get all videos list, body: $body");

        final map = jsonDecode(body);
        final httpResponseEntity = ResponseEntity.fromJson(map);

        if (httpResponseEntity.isSuccessful()) {
          final data = httpResponseEntity.data as List<dynamic>;

          onSuccess.call(data
              .map((e) => VideoFolderItem.fromJson(e as Map<String, dynamic>))
              .toList());
        } else {
          onError.call(httpResponseEntity.msg == null
              ? "Unknown error"
              : httpResponseEntity.msg!);
        }
      }
    }).catchError((error) {
      onError.call(error.toString());
    });
  }

  void _getVideosInFolder(String folderId,
      Function(List<VideoItem> videos) onSuccess,
      Function(String error) onError) {
    var url = Uri.parse("${_URL_SERVER}/video/videosInFolder");
    http.post(url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"folderId": folderId}))
        .then((response) {
      if (response.statusCode != 200) {
        onError.call(response.reasonPhrase != null
            ? response.reasonPhrase!
            : "Unknown error");
      } else {
        var body = response.body;
        debugPrint("Get all videos list, body: $body");

        final map = jsonDecode(body);
        final httpResponseEntity = ResponseEntity.fromJson(map);

        if (httpResponseEntity.isSuccessful()) {
          final data = httpResponseEntity.data as List<dynamic>;

          onSuccess.call(data
              .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
              .toList());
        } else {
          onError.call(httpResponseEntity.msg == null
              ? "Unknown error"
              : httpResponseEntity.msg!);
        }
      }
    }).catchError((error) {
      onError.call(error.toString());
    });
  }

  // 回到相册列表页面
  void _backVideoFoldersPage() {
    setState(() {
      _openVideosInFolderPage = false;
      _isLoadingVideosInFolderCompleted = false;
      _videosInFolder = [];
      _selectedVideosInFolder = [];
      updateDeleteBtnStatus();
      updateBottomItemNum();
      _setBackBtnVisible(false);
    });
  }

  void _clearSelectedVideosInFolder() {
    setState(() {
      _selectedVideosInFolder.clear();
      updateBottomItemNum();
      _setDeleteBtnEnabled(false);
    });
  }

  Widget _createVideosWidget() {
    return VideoFlowWidget(
      videos: _videosInFolder,
      selectedVideos: _selectedVideosInFolder,
      sortOrder: _currentSortOrder,
      onVideoTap: (video) {
        _setVideoSelected(video);
      },
      onOutsideTap: () {
        _clearSelectedVideosInFolder();
      },
      onVisibleChange: (totalVisible, partOfVisible) {
        setState(() {
          _isVideosInFolderPageVisible = totalVisible;
          if (_isVideosInFolderPageVisible) {
            updateBottomItemNum();
          }
        });
      },
      onVideoDoubleTap: (video) {
        _openVideoWithSystemApp(video);
      },
      onPointerDown: (event, video) {
        if (_isMouseRightClicked(event)) {
          _showMenu(event.position, video);
        }
      },
    );
  }

  bool _isMouseRightClicked(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryMouseButton;
  }

  void _showMenu(Offset position, dynamic item) {
    if (item! is VideoFolderItem && item! is VideoItem) {
      throw "item must be one of VideoFolderItem or VideoItem";
    }

    RenderBox? overlay =
    Overlay
        .of(context)
        ?.context
        .findRenderObject() as RenderBox;

    String copyTitle = "";

    if (item is VideoFolderItem) {
      if (_selectedVideoFolders.length == 1) {
        copyTitle = "拷贝${_selectedVideoFolders.single.name}到电脑";
      } else {
        copyTitle = "拷贝 ${_selectedVideoFolders.length} 项 到 电脑";
      }
    }

    if (item is VideoItem) {
      if (_selectedVideosInFolder.length == 1) {
        copyTitle = "拷贝${_selectedVideosInFolder.single.name}到电脑";
      } else {
        copyTitle = "拷贝 ${_selectedVideosInFolder.length} 项 到 电脑";
      }
    }

    showMenu(
        context: context,
        position: RelativeRect.fromSize(
            Rect.fromLTRB(position.dx, position.dy, 0, 0),
            overlay.size),
        items: [
          PopupMenuItem(
              child: Text("打开"),
              onTap: () {
                if (item is VideoItem) {
                  _openVideoWithSystemApp(item);
                } else {
                  _currentVideoFolder = item;
                  _tryToOpenVideosInFolderPage(item);
                }
              }),
          PopupMenuItem(
              child: Text(copyTitle),
              onTap: () {
                _openFilePicker((dir) {
                  if (item is VideoFolderItem) {
                    _startDownload(true, dir);
                  }

                  if (item is VideoItem) {
                    _startDownload(false, dir);
                  }
                }, (error) {
                  debugPrint("_openFilePicker, error: $error");
                });
              }),
          PopupMenuItem(
              child: Text("删除"),
              onTap: () {
                Future<void>.delayed(const Duration(), () {
                  if (item is VideoFolderItem) {
                    _tryToDeleteVideoFolders(_selectedVideoFolders);
                  } else {
                    _tryToDeleteVideos(_selectedVideosInFolder);
                  }
                });
              }),
        ]);
  }

  void _openFilePicker(void onSuccess(String dir), void onError(String error)) {
    FilePicker.platform.getDirectoryPath(dialogTitle: "选择目录", lockParentWindow: true)
        .then((value) {
          if (null == value) {
            onError.call("Dir is null");
          } else {
            onSuccess.call(value);
          }
    }).catchError((error) {
      onError.call(error);
    });
  }

  void _startDownload(bool isDownloadFolders, String dir) {
    List<String> paths = _selectedVideoFolders.map((folder) => folder.path).toList();

    if (!isDownloadFolders) {
      paths = _selectedVideosInFolder.map((video) => video.path).toList();
    }

    _showDownloadProgressDialog(isDownloadFolders);

    _downloadFiles(paths, dir, () {
      _progressIndicatorDialog?.dismiss();
    }, (error) {
      SmartDialog.showToast(error);
    }, (current, total) {
      if (_progressIndicatorDialog?.isShowing == true) {
        if (current > 0) {
          setState(() {
            String title = "视频导出中，请稍后...";

            if (isDownloadFolders) {
              if (_selectedVideoFolders.length > 1) {
                title = "正在导出${_selectedVideoFolders.length}个视频文件夹";
              }

              if (_selectedVideoFolders.length == 1) {
                title = "正在导出视频文件夹${_selectedVideoFolders.single.name}";
              }
            } else {
              if (_selectedVideosInFolder.length > 1) {
                title = "正在导出${_selectedVideosInFolder.length}个视频文件夹";
              }

              if (_selectedVideosInFolder.length == 1) {
                title = "正在导出视频${_selectedVideosInFolder.single.name}";
              }
            }

            _progressIndicatorDialog?.title = title;
          });
        }

        setState(() {
          _progressIndicatorDialog?.subtitle =
          "${_convertToReadableSize(current)}/${_convertToReadableSize(
              total)}";
          _progressIndicatorDialog?.updateProgress(current / total);
        });
      }
    });
  }

  void _downloadFiles(List<String> paths, String dir, void onSuccess(),
      void onError(String error), void onDownload(current, total)) async {
    String name = "";

    if (paths.length <= 1) {
      String path = paths.single;
      int index = path.lastIndexOf("/");
      if (index != -1) {
        name = path.substring(index + 1);
      }
    } else {
      final df = DateFormat("yyyyMd_HHmmss");

      String formatTime = df.format(new DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch));

      name = "AirController_${formatTime}.zip";
    }

    var options = DownloaderUtils(
        progress: ProgressImplementation(),
        file: File("$dir/$name"),
        onDone: () {
          onSuccess.call();
        },
        progressCallback: (current, total) {
          debugPrint("total: $total, current: $current");

          onDownload.call(current, total);
        });

    String pathsStr =  Uri.encodeComponent(jsonEncode(paths));

    String api = "${_URL_SERVER}/stream/download?paths=$pathsStr";

    if (null == _downloaderCore) {
      _downloaderCore = await Flowder.download(api, options);
    } else {
      _downloaderCore?.download(api, options);
    }
  }
  
  void _showConfirmDialog(
      String content,
      String desc,
      String negativeText,
      String positiveText,
      Function(BuildContext context) onPositiveClick,
      Function(BuildContext context) onNegativeClick) {
    Dialog dialog = ConfirmDialogBuilder()
        .content(content)
        .desc(desc)
        .negativeBtnText(negativeText)
        .positiveBtnText(positiveText)
        .onPositiveClick(onPositiveClick)
        .onNegativeClick(onNegativeClick)
        .build();

    showDialog(
        context: context,
        builder: (context) {
          return dialog;
        },
        barrierDismissible: false);
  }

  void _deleteVideos(List<VideoItem> videos, Function() onSuccess,
      Function(String error) onError) {
    var url = Uri.parse("${_URL_SERVER}/file/deleteMulti");
    http
        .post(url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "paths": videos
              .map((node) => node.path)
              .toList()
        }))
        .then((response) {
      if (response.statusCode != 200) {
        onError.call(response.reasonPhrase != null
            ? response.reasonPhrase!
            : "Unknown error");
      } else {
        var body = response.body;
        debugPrint("_deleteFiles, body: $body");

        final map = jsonDecode(body);
        final httpResponseEntity = ResponseEntity.fromJson(map);

        if (httpResponseEntity.isSuccessful()) {
          onSuccess.call();
        } else {
          onError.call(httpResponseEntity.msg == null
              ? "Unknown error"
              : httpResponseEntity.msg!);
        }
      }
    }).catchError((error) {
      onError.call(error.toString());
    });
  }

  void _deleteVideoFolders(List<VideoFolderItem> videos, Function() onSuccess,
      Function(String error) onError) {
    var url = Uri.parse("${_URL_SERVER}/file/deleteMulti");
    http
        .post(url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "paths": videos
              .map((node) => node.path)
              .toList()
        }))
        .then((response) {
      if (response.statusCode != 200) {
        onError.call(response.reasonPhrase != null
            ? response.reasonPhrase!
            : "Unknown error");
      } else {
        var body = response.body;
        debugPrint("_deleteFiles, body: $body");

        final map = jsonDecode(body);
        final httpResponseEntity = ResponseEntity.fromJson(map);

        if (httpResponseEntity.isSuccessful()) {
          onSuccess.call();
        } else {
          onError.call(httpResponseEntity.msg == null
              ? "Unknown error"
              : httpResponseEntity.msg!);
        }
      }
    }).catchError((error) {
      onError.call(error.toString());
    });
  }
  
  void _tryToDeleteVideos(List<VideoItem> videos) {
    _showConfirmDialog("确定删除这${videos.length}个项目吗？", "注意：删除的文件无法恢复", "取消", "删除",
            (context) {
          Navigator.of(context, rootNavigator: true).pop();

          SmartDialog.showLoading();

          _deleteVideos(videos, () {
            SmartDialog.dismiss();

            setState(() {
              _videosInFolder.removeWhere((element) => videos.contains(element));
              _selectedVideosInFolder.clear();
              _setDeleteBtnEnabled(false);
            });
          }, (error) {
            SmartDialog.dismiss();

            SmartDialog.showToast(error);
          });
        }, (context) {
          Navigator.of(context, rootNavigator: true).pop();
        });
  }

  void _tryToDeleteVideoFolders(List<VideoFolderItem> videoFolders) {
    _showConfirmDialog("确定删除这${videoFolders.length}个项目吗？", "注意：删除的文件无法恢复", "取消", "删除",
            (context) {
          Navigator.of(context, rootNavigator: true).pop();

          SmartDialog.showLoading();

          _deleteVideoFolders(videoFolders, () {
            SmartDialog.dismiss();

            setState(() {
              _videoFolders.removeWhere((element) => videoFolders.contains(element));
              _selectedVideoFolders.clear();
              _setDeleteBtnEnabled(false);
            });
          }, (error) {
            SmartDialog.dismiss();

            SmartDialog.showToast(error);
          });
        }, (context) {
          Navigator.of(context, rootNavigator: true).pop();
        });
  }

  String _convertToReadableSize(int size) {
    if (size < _KB_BOUND) {
      return "${size} bytes";
    }
    if (size >= _KB_BOUND && size < _MB_BOUND) {
      return "${(size / 1024).toStringAsFixed(1)} KB";
    }

    if (size >= _MB_BOUND && size <= _GB_BOUND) {
      return "${(size / 1024 / 1024).toStringAsFixed(1)} MB";
    }

    return "${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB";
  }

  void _showDownloadProgressDialog(bool isDownloadFolders) {
    if (null == _progressIndicatorDialog) {
      _progressIndicatorDialog = ProgressIndicatorDialog(context: context);
      _progressIndicatorDialog?.onCancelClick(() {
        _downloaderCore?.cancel();
        _progressIndicatorDialog?.dismiss();
      });
    }

    String title = "正在准备中，请稍后...";

    if (isDownloadFolders) {
      title = "正在压缩中，请稍后...";
    } else {
      if (_selectedVideosInFolder.length > 1) {
        title = "正在压缩中，请稍后...";
      }
    }

    _progressIndicatorDialog?.title = title;

    if (!_progressIndicatorDialog!.isShowing) {
      _progressIndicatorDialog!.show();
    }
  }

  void _openVideoWithSystemApp(VideoItem videoItem) async {
    String videoUrl = "http://${DeviceConnectionManager.instance.currentDevice?.ip}:${Constant.PORT_HTTP}/video/item/${videoItem.id}";

    if (!await launch(
        videoUrl,
        universalLinksOnly: true
    )) {
      debugPrint("Open video: $videoUrl fail");
    } else {
      debugPrint("Open video: $videoUrl success");
    }
  }

  void _tryToOpenVideosInFolderPage(VideoFolderItem folder) {
    setState(() {
      _openVideosInFolderPage = true;
      _setBackBtnVisible(true);
      _getVideosInFolder(folder.id, (videos) {
        _videosInFolder = videos;
        _isLoadingVideosInFolderCompleted = true;
      }, (error) {
        debugPrint("_tryToOpenVideosInFolderPage, error: $error");
        _isLoadingVideosInFolderCompleted = true;
      });
    });
  }

  @override
  void deactivate() {
    super.deactivate();
    _rootFocus1?.unfocus();
  }

  @override
  void activate() {
    super.activate();
    _rootFocus1?.requestFocus();
  }

  @override
  void dispose() {
    super.dispose();

    _unRegisterEventBus();

    _rootFocus1?.requestFocus();
    _rootFocus2?.requestFocus();
  }

  @override
  bool get wantKeepAlive => true;
}
