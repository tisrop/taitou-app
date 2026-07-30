import '../site_customization.dart';

/// 开源心声社区（openxinsheng.com）站点自定义配置
///
/// 头像光晕与头衔特效依赖站点自建的群组/头衔命名，openxinsheng 的群组结构
/// 站点群组结构尚未稳定，暂不配置；后续按需补 [AvatarGlowRule]。
final openxinshengCustomization = SiteCustomization(
  discourseReactionsEnabled: true,
  gamificationEnabled: true,
  gamificationLeaderboardId: 1,
  linkSecurityConfig: _openxinshengLinkSecurityConfig,
);

/// 开源心声链接安全配置
///
/// 内网域名与短链风险名单沿用通用规则；其他站点专属的 trusted/blocked
/// 名单与本站无关，已移除。
const _openxinshengLinkSecurityConfig = LinkSecurityConfig(
  enableExitConfirmation: true,
  internalDomains: [
    '*.openxinsheng.com',
    'localhost',
    '*.local',
    '^127(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}',
    '^10(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}',
    '^169\\.254(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
    '^192\\.168(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
    '^172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){2}',
  ],
  riskyDomains: [
    // 通用短链服务，与站点无关
    'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'ow.ly', 'buff.ly',
    'adf.ly', 'short.link', '*.short.link', 'tiny.cc', 'is.gd',
    'cli.gs', 'pic.gd', 'dwarfurl.com', 'yfrog.com', 'migre.me',
    'ff.im', 'tiny.pl', 'url4.eu', 'tr.im', 'twit.ac', 'su.pr',
    'twurl.nl', 'snipurl.com', 'budurl.com', 'short.to', 'ping.fm',
    'digg.com', 'post.ly', 'just.as', 'bkite.com', 'snipr.com',
    'fic.kr', 'loopt.us', 'doiop.com', 'twitthis.com', 'htxt.it',
    'alturl.com', 'redirx.com', 'digbig.com', 'short.ie',
    'u.mavrev.com', 'kl.am', 'wp.me', 'rubyurl.com', 'om.ly',
    'to.ly', 'bit.do', 'lnkd.in', 'db.tt', 'qr.ae', 'bitly.com',
    'cur.lv', 'ity.im', 'q.gs', 'po.st', 'bc.vc', 'u.to', 'j.mp',
    'buzurl.com', 'cutt.us', 'u.bb', 'yourls.org', 'x.co',
    'prettylinkpro.com', 'scrnch.me', 'filoops.info', 'vzturl.com',
    'qr.net', '1url.com', 'tweez.me', 'v.gd', 'link.zip',
  ],
  dangerousDomains: ['**aff='],
);
