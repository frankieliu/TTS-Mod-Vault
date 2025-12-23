enum DownloadErrorTypeEnum {
  permanent('Permanent Error'),
  temporary('Temporary Error'),
  unknown('Unknown Error');

  final String label;
  const DownloadErrorTypeEnum(this.label);
}
