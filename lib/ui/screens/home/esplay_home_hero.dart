import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../widgets/bounded_network_image.dart';

/// EsPlay: the top of Home on a TV while the rows have focus, as on Samsung.
/// The title under the remote shows its picture on the right, fading into the
/// background towards the text and the row below, with its logo or name,
/// details and synopsis. When it has a preview, [video] plays there instead of
/// inside the card. [unit] is a 1920-wide screen's pixel, [textInset] where
/// Home's rows start.
class EsplayMediaHero extends StatefulWidget {
  final AggregatedItem item;
  final double unit;
  final double textInset;
  final Widget? video;

  const EsplayMediaHero({
    super.key,
    required this.item,
    required this.unit,
    required this.textInset,
    this.video,
  });

  static double heightFor(double unit) => 370 * unit;

  @override
  State<EsplayMediaHero> createState() => _EsplayMediaHeroState();
}

class _EsplayMediaHeroState extends State<EsplayMediaHero> {
  bool _logoFailed = false;

  @override
  void didUpdateWidget(EsplayMediaHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) _logoFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final u = widget.unit;
    final width = MediaQuery.sizeOf(context).width;
    ImageApi images() => GetIt.instance<MediaServerClientFactory>()
        .clientForServerOrActive(item.serverId)
        .imageApi;
    final picture = _pictureUrl(item, images);
    final logo = _logoUrl(item, images);
    final title = item.type == 'Episode' && (item.seriesName ?? '').isNotEmpty
        ? item.seriesName!
        : item.name;
    final details = _details(item);
    final overview = item.overview?.trim() ?? '';
    final background = AppColorScheme.background;

    // Fades [child] to nothing from the [from] edge, solid from the last stop on.
    Widget fade(Widget child, Alignment from, List<double> stops) => ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: from,
            end: -from,
            colors: const [
              Color(0x00000000),
              Color(0x00000000),
              Color(0x80000000),
              Color(0xFF000000),
            ],
            stops: stops,
          ).createShader(rect),
          child: child,
        );
    // A video can't be masked, so the same fade is laid over it instead.
    Widget shade(Alignment from, List<double> stops) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: from,
                end: -from,
                colors: [
                  background,
                  background,
                  background.withAlpha(128),
                  background.withAlpha(0),
                ],
                stops: stops,
              ),
            ),
          ),
        );
    const leftStops = [0.0, 0.10, 0.34, 0.62];
    const bottomStops = [0.0, 0.06, 0.30, 0.55];

    final Widget art;
    if (widget.video != null) {
      art = Stack(
        fit: StackFit.expand,
        children: [
          widget.video!,
          shade(Alignment.centerLeft, leftStops),
          shade(Alignment.bottomCenter, bottomStops),
        ],
      );
    } else if (picture != null) {
      art = fade(
        fade(
          BoundedNetworkImage(
            key: ValueKey(picture),
            imageUrl: picture,
            fit: BoxFit.cover,
            maxWidth: 1280,
            errorBuilder: (context, url, error) => const SizedBox.shrink(),
          ),
          Alignment.bottomCenter,
          bottomStops,
        ),
        Alignment.centerLeft,
        leftStops,
      );
    } else {
      art = const SizedBox.shrink();
    }

    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 56 * u,
      height: 1.05,
      fontWeight: FontWeight.w800,
    );
    final titleText = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );

    return ColoredBox(
      color: background,
      child: SizedBox(
        height: EsplayMediaHero.heightFor(u),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: width * 0.66,
              child: ClipRect(child: art),
            ),
            Positioned(
              left: widget.textInset,
              bottom: 26 * u,
              width: width * 0.46,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (logo != null && !_logoFailed)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 460 * u,
                        maxHeight: 130 * u,
                      ),
                      child: BoundedNetworkImage(
                        key: ValueKey(logo),
                        imageUrl: logo,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomLeft,
                        maxWidth: 600,
                        errorBuilder: (context, url, error) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _logoFailed = true);
                          });
                          return titleText;
                        },
                      ),
                    )
                  else
                    titleText,
                  if (details.isNotEmpty) ...[
                    SizedBox(height: 14 * u),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFC4C4CA),
                        fontSize: 24 * u,
                      ),
                    ),
                  ],
                  if (overview.isNotEmpty) ...[
                    SizedBox(height: 14 * u),
                    Text(
                      overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFA8A8B0),
                        fontSize: 22 * u,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Its backdrop, else its parent's, else an outside list's, else its own
  /// wide or upright picture.
  static String? _pictureUrl(AggregatedItem item, ImageApi Function() images) {
    final backdrops = item.backdropImageTags;
    if (backdrops.isNotEmpty) {
      return images().getBackdropImageUrl(item.id, maxWidth: 1280, index: 0, tag: backdrops.first);
    }
    final parentId = item.parentBackdropItemId;
    final parentTags = item.parentBackdropImageTags;
    if (parentId != null && parentTags.isNotEmpty) {
      return images().getBackdropImageUrl(parentId, maxWidth: 1280, index: 0, tag: parentTags.first);
    }
    final path = item.rawData['BackdropPath'] as String?;
    if (path != null && path.startsWith('http')) return path;
    if (path != null && path.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/w1280$path';
    }
    final thumb = item.thumbImageTag;
    if (thumb != null) {
      return images().getThumbImageUrl(item.id, maxWidth: 1280, tag: thumb);
    }
    final primary = item.primaryImageTag;
    if (primary != null) {
      return images().getPrimaryImageUrl(item.id, maxWidth: 1280, tag: primary);
    }
    return null;
  }

  static String? _logoUrl(AggregatedItem item, ImageApi Function() images) {
    final own = item.logoImageTag;
    if (own != null) {
      return images().getLogoImageUrl(item.id, maxWidth: 600, tag: own);
    }
    final parentId = item.rawData['ParentLogoItemId']?.toString();
    final parentTag = item.seriesLogoImageTag;
    if (parentId != null && parentTag != null) {
      return images().getLogoImageUrl(parentId, maxWidth: 600, tag: parentTag);
    }
    return null;
  }

  static String _details(AggregatedItem item) {
    final parts = <String>[];
    if (item.type == 'Episode') {
      final season = item.parentIndexNumber;
      final episode = item.indexNumber;
      final number =
          season != null && episode != null ? 'T$season:E$episode' : '';
      parts.add([number, item.name].where((s) => s.isNotEmpty).join(' · '));
    }
    if (item.productionYear != null) parts.add('${item.productionYear}');
    if ((item.officialRating ?? '').isNotEmpty) parts.add(item.officialRating!);
    if (item.communityRating != null) {
      parts.add('★ ${item.communityRating!.toStringAsFixed(1)}');
    }
    final runtime = item.runtime;
    if (runtime != null && item.type != 'Series' && runtime.inMinutes > 0) {
      final h = runtime.inHours;
      final m = runtime.inMinutes % 60;
      parts.add(h > 0 ? '${h}h ${m}m' : '${m}m');
    }
    if (item.genres.isNotEmpty) parts.add(item.genres.take(3).join(', '));
    return parts.join(' · ');
  }
}
