// Synthetic player with EJS's URL-transform call site. No provider data.
var _yt_player = {};
(function(g) {
  var initial = 0;
  var config = {signatureTimestamp: 20300};
  function MediaURL(url) { this.params = {}; }
  MediaURL.prototype.set = function(k, v) { this.params[k] = v; };
  MediaURL.prototype.get = function(k) { return this.params[k]; };
  MediaURL.prototype.decode = function() {
    if (this.get('s')) this.set('s', this.get('s').split('').reverse().join(''));
    if (this.get('n')) this.set('n', this.get('n') + '_decoded');
  };
  function transform(url, key, sig) {
    var result = new MediaURL(url);
    result.set('alr', 'yes');
    if (sig) result.set(key, decodeURIComponent(sig));
    return result;
  }
})(_yt_player);
