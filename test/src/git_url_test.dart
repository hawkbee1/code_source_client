import 'package:code_source_client/code_source_client.dart';
import 'package:test/test.dart';

void main() {
  group(GitUrl, () {
    group('tryParse', () {
      const github = GitUrl(host: GitHost.github, path: 'TalaoDAO/AltMe');

      for (final input in [
        'https://github.com/TalaoDAO/AltMe',
        'https://github.com/TalaoDAO/AltMe.git',
        'https://github.com/TalaoDAO/AltMe/',
        'http://www.github.com/TalaoDAO/AltMe',
        'git@github.com:TalaoDAO/AltMe.git',
        'ssh://git@github.com/TalaoDAO/AltMe.git',
        'github.com/TalaoDAO/AltMe',
        '  https://github.com/TalaoDAO/AltMe  ',
      ]) {
        test('parses "$input"', () {
          expect(GitUrl.tryParse(input), github);
        });
      }

      test('reads the ref of a GitHub browser URL', () {
        expect(
          GitUrl.tryParse('https://github.com/o/r/tree/feature/x'),
          const GitUrl(host: GitHost.github, path: 'o/r', ref: 'feature/x'),
        );
      });

      test('parses GitLab URLs with subgroups and a browser ref', () {
        expect(
          GitUrl.tryParse('https://gitlab.com/group/sub/repo.git'),
          const GitUrl(host: GitHost.gitlab, path: 'group/sub/repo'),
        );
        expect(
          GitUrl.tryParse('gitlab.com/group/repo/-/tree/v1.0'),
          const GitUrl(host: GitHost.gitlab, path: 'group/repo', ref: 'v1.0'),
        );
      });

      for (final input in [
        '',
        'AltMe',
        'https://bitbucket.org/o/r',
        'https://github.com/o',
        'https://github.com/o/r/extra',
        'https://github.com/o/r r',
        'https://gitlab.com/onlyone',
      ]) {
        test('returns null for "$input"', () {
          expect(GitUrl.tryParse(input), isNull);
        });
      }
    });

    test('exposes the repository name', () {
      expect(const GitUrl(host: GitHost.gitlab, path: 'g/s/repo').name, 'repo');
    });

    group('archiveUri', () {
      test('points at the GitHub zipball, with or without ref', () {
        const url = GitUrl(host: GitHost.github, path: 'o/r');

        expect(
          url.archiveUri().toString(),
          'https://api.github.com/repos/o/r/zipball',
        );
        expect(
          url.archiveUri(ref: 'feature/x').toString(),
          'https://api.github.com/repos/o/r/zipball/feature%2Fx',
        );
      });

      test('points at the GitLab archive of a ref', () {
        const url = GitUrl(host: GitHost.gitlab, path: 'g/r');

        expect(
          url.archiveUri(ref: 'main').toString(),
          'https://gitlab.com/g/r/-/archive/main/r-main.zip',
        );
        expect(
          url.archiveUri(ref: 'feat/x').toString(),
          'https://gitlab.com/g/r/-/archive/feat%2Fx/r-feat-x.zip',
        );
      });

      test('needs a ref on GitLab', () {
        const url = GitUrl(host: GitHost.gitlab, path: 'g/r');

        expect(url.archiveUri, throwsArgumentError);
      });
    });

    test('points at the GitLab project API with an encoded path', () {
      expect(
        const GitUrl(
          host: GitHost.gitlab,
          path: 'g/s/r',
        ).gitlabProjectUri.toString(),
        'https://gitlab.com/api/v4/projects/g%2Fs%2Fr',
      );
    });
  });
}
