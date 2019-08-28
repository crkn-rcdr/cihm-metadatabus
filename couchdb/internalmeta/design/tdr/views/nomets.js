module.exports = {
  map: function(doc) {
    if (!("METS" in doc)) {
      emit(null, null);
    }
  }
};
