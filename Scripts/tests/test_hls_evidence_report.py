"""Report/schema regression controls; no synthetic file is release evidence."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('apple_report', ROOT / 'Scripts/check_apple_hls_report.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def report(body='', version='1.3'):
    return ('<html><body><h2>HLS Validation Report</h2>' + body +
            '<h3>Report Information</h3><p>JSON format version: ' + version + '</p></body></html>')


class ReportTests(unittest.TestCase):
    def check(self, html):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.html'
            path.write_text(html)
            checker.validate(path)

    def test_unsupported_report_never_passes_with_report_information(self):
        with self.assertRaises(SystemExit):
            self.check(report('Version 3 output is not understood.', '3.1'))

    def test_unknown_or_missing_format_version_rejected(self):
        for value in ['4.0', '1.4', 'unknown']:
            with self.subTest(value=value), self.assertRaises(SystemExit):
                self.check(report(version=value))
        with self.assertRaises(SystemExit):
            self.check('<h3>Report Information</h3>')

    def test_earlier_must_fix_section_cannot_be_hidden_by_later_empty_section(self):
        with self.assertRaises(SystemExit):
            self.check(report('<h3>Must Fix Issues</h3>Invalid segment'
                              '<h3>Should Fix Issues</h3>Advice'
                              '<h3>Authoring Spec Must Fix Issues</h3>None'))

    def test_critical_and_authoring_must_fix_sections_rejected(self):
        for heading in ['Critical Must Fix Issues', 'Authoring Spec Must Fix Issues']:
            with self.subTest(heading=heading), self.assertRaises(SystemExit):
                self.check(report('<h3>' + heading + '</h3>Invalid media'))

    def test_advisories_remain_allowed_and_visible(self):
        self.check(report('<h3>Authoring Spec Should Fix Issues</h3>Use TLS'
                          '<h3>Advisories</h3>Independent segments advice'))

    def test_missing_title_empty_must_fix_and_extra_version_rejected(self):
        for html in ['<h3>Report Information</h3>JSON format version: 1.3',
                     report('<h3>Must Fix Issues</h3>'),
                     report(version='1.3.0'), report(version='1.3 JSON format version: 1.3')]:
            with self.subTest(html=html), self.assertRaises(SystemExit): self.check(html)

    def test_script_text_is_not_report_content(self):
        self.check(report('<script>Unsupported fake Must Fix Issues</script>'
                          '<style>unsupported: invalid;</style>'))


class ValidatorDataTests(unittest.TestCase):
    def data(self):
        return {'dataVersion': 1.3, 'dataStatus': 1, 'validatorName': 'mediastreamvalidator',
                'validatorVersion': 'UNIT-TEST-NOT-APPLE', 'playlistKind': 'media',
                'processedSegmentsCount': 1, 'messages': [],
                'discontinuities': [{'segments': [{}]}]}

    def test_schema_and_completion_are_required(self):
        for key, value in [('dataVersion', 3.1), ('dataVersion', 2.3), ('dataVersion', True),
                           ('dataStatus', 0), ('dataStatus', True), ('processedSegmentsCount', 0),
                           ('discontinuities', []), ('validatorName', 'fixture')]:
            data = self.data(); data[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(SystemExit):
                checker.validate_data(data)

    def test_nested_blocking_or_unknown_message_cannot_hide(self):
        for message in [{'errorStatusCode': 433088}, {'errorStatusCode': 435018},
                        {'errorStatusCode': 600001}, {'errorStatusCode': True}, {},
                        {'errorStatusCode': 900001}]:
            data = self.data(); data['discontinuities'][0]['segments'][0]['messages'] = [message]
            with self.subTest(message=message), self.assertRaises(SystemExit):
                checker.validate_data(data)

    def test_advisory_and_should_codes_remain_allowed(self):
        data = self.data()
        data['messages'] = [{'errorStatusCode': 135048}, {'errorStatusCode': 235042}]
        self.assertEqual(checker.validate_data(data), 1.3)

    def test_no_issue_json_may_omit_messages_but_invalid_message_type_fails(self):
        data = self.data(); del data['messages']
        self.assertEqual(checker.validate_data(data), 1.3)
        for value in [None, {}, '']:
            data['messages'] = value
            with self.subTest(value=value), self.assertRaises(SystemExit): checker.validate_data(data)

    def test_duplicate_json_key_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'validator.json'
            path.write_text('{"dataVersion":3.1,"dataVersion":1.3}')
            with self.assertRaises(SystemExit): checker.read_validation_json(path)

    def test_report_and_json_are_both_validated(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'report.html'; path.write_text(report())
            checker.validate(path, self.data())
            data = self.data(); data['messages'] = [{'errorStatusCode': 435018}]
            with self.assertRaises(SystemExit): checker.validate(path, data)


if __name__ == '__main__':
    unittest.main()
