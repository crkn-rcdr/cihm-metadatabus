module.exports = {
  map: function(doc) {
    if (doc._attachments) {
      for (var key in doc._attachments) {
        // output filename, filesize, docId
        emit([key, doc._attachments[key].length, doc._id], 1);
      }
    }
  }
};
