import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

void main() {
  test(
    'post-voting service uses plugin request contracts and parses responses',
    () async {
      final service = DiscourseService();
      final dio = service.dio;
      final originalAdapter = dio.httpClientAdapter;
      final originalInterceptors = dio.interceptors.toList(growable: false);
      final adapter = _PostVotingAdapter();

      dio.interceptors.clear();
      dio.httpClientAdapter = adapter;
      addTearDown(() {
        dio.httpClientAdapter = originalAdapter;
        dio.interceptors
          ..clear()
          ..addAll(originalInterceptors);
      });

      await service.postVotingVote(postId: 10, direction: 'up');
      await service.postVotingRemoveVote(postId: 10);
      final (voters, total) = await service.getPostVotingVoters(10);
      final comments = await service.getPostVotingComments(
        postId: 10,
        lastCommentId: 4,
      );
      final created = await service.createPostVotingComment(
        postId: 10,
        raw: 'new comment',
      );
      await service.votePostVotingComment(commentId: 5, vote: true);
      await service.votePostVotingComment(commentId: 5, vote: false);

      expect(adapter.requests, hasLength(7));

      final vote = adapter.requests[0];
      expect(vote.method, 'POST');
      expect(vote.path, '/post_voting/vote');
      expect(vote.data, {'post_id': 10, 'direction': 'up'});
      expect(vote.contentType, Headers.formUrlEncodedContentType);

      final removeVote = adapter.requests[1];
      expect(removeVote.method, 'DELETE');
      expect(removeVote.path, '/post_voting/vote');
      expect(removeVote.data, {'post_id': 10});

      final voterRequest = adapter.requests[2];
      expect(voterRequest.method, 'GET');
      expect(voterRequest.path, '/post_voting/voters');
      expect(voterRequest.queryParameters, {'post_id': 10});
      expect(total, 2);
      expect(voters, hasLength(1));
      expect(voters.single.username, 'alice');
      expect(voters.single.direction, 'up');

      final commentRequest = adapter.requests[3];
      expect(commentRequest.method, 'GET');
      expect(commentRequest.path, '/post_voting/comments');
      expect(commentRequest.queryParameters, {
        'post_id': 10,
        'last_comment_id': 4,
      });
      expect(comments.single.id, 5);
      expect(comments.single.voteCount, 2);

      final createRequest = adapter.requests[4];
      expect(createRequest.method, 'POST');
      expect(createRequest.path, '/post_voting/comments');
      expect(createRequest.data, {'post_id': 10, 'raw': 'new comment'});
      expect(created.id, 6);
      expect(created.raw, 'new comment');

      final commentVote = adapter.requests[5];
      expect(commentVote.method, 'POST');
      expect(commentVote.path, '/post_voting/vote/comment');
      expect(commentVote.data, {'comment_id': 5});

      final commentUnvote = adapter.requests[6];
      expect(commentUnvote.method, 'DELETE');
      expect(commentUnvote.path, '/post_voting/vote/comment');
      expect(commentUnvote.data, {'comment_id': 5});
    },
  );
}

class _PostVotingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    final Object body;
    if (options.path == '/post_voting/voters') {
      body = {
        'voters': [
          {'username': 'alice', 'direction': 'up'},
        ],
        'total_voters_count': 2,
      };
    } else if (options.path == '/post_voting/comments' &&
        options.method == 'GET') {
      body = {
        'comments': [
          {
            'id': 5,
            'username': 'bob',
            'raw': 'existing comment',
            'cooked': '<p>existing comment</p>',
            'post_voting_vote_count': 2,
          },
        ],
      };
    } else if (options.path == '/post_voting/comments' &&
        options.method == 'POST') {
      body = {
        'id': 6,
        'username': 'me',
        'raw': 'new comment',
        'cooked': '<p>new comment</p>',
      };
    } else {
      body = <String, dynamic>{};
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
