import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/category.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('post-voting models', () {
    test('Category parses plugin capability and category defaults', () {
      final category = Category.fromJson({
        'id': 7,
        'name': 'Q&A',
        'create_as_post_voting_default': true,
        'only_post_voting_in_this_category': true,
      });

      expect(category.createAsPostVotingDefault, isTrue);
      expect(category.onlyPostVotingInThisCategory, isTrue);
      expect(category.hasPostVotingFields, isTrue);

      final regular = Category.fromJson({'id': 8, 'name': 'General'});
      expect(regular.createAsPostVotingDefault, isFalse);
      expect(regular.onlyPostVotingInThisCategory, isFalse);
      expect(regular.hasPostVotingFields, isFalse);
    });

    test('PostVotingComment parses and copies vote state', () {
      final comment = PostVotingComment.fromJson({
        'id': 31,
        'user_id': 9,
        'name': 'Alice',
        'username': 'alice',
        'created_at': '2026-08-10T08:00:00.000Z',
        'raw': 'raw comment',
        'cooked': '<p>raw comment</p>',
        'post_voting_vote_count': 4.0,
        'user_voted': true,
      });

      expect(comment.id, 31);
      expect(comment.userId, 9);
      expect(comment.username, 'alice');
      expect(comment.createdAt, isNotNull);
      expect(comment.voteCount, 4);
      expect(comment.userVoted, isTrue);

      final updated = comment.copyWith(voteCount: 3, userVoted: false);
      expect(updated.voteCount, 3);
      expect(updated.userVoted, isFalse);
      expect(updated.raw, comment.raw);
      expect(updated.cooked, comment.cooked);
    });

    test('Post parses answer votes and comments and can clear direction', () {
      final post = Post.fromJson({
        'id': 42,
        'username': 'answerer',
        'post_number': 2,
        'post_voting_vote_count': -2.0,
        'post_voting_user_voted_direction': 'down',
        'post_voting_has_votes': true,
        'comments_count': 3.0,
        'comments': [
          {
            'id': 51,
            'username': 'commenter',
            'raw': 'why?',
            'cooked': '<p>why?</p>',
            'post_voting_vote_count': 1,
            'user_voted': false,
          },
        ],
      });

      expect(post.postVotingVoteCount, -2);
      expect(post.postVotingUserVotedDirection, 'down');
      expect(post.postVotingHasVotes, isTrue);
      expect(post.postVotingCommentsCount, 3);
      expect(post.postVotingComments, hasLength(1));
      expect(post.postVotingComments!.single.id, 51);

      final updated = post.copyWith(
        postVotingVoteCount: 0,
        clearPostVotingDirection: true,
        postVotingHasVotes: false,
        postVotingCommentsCount: 1,
      );
      expect(updated.postVotingVoteCount, 0);
      expect(updated.postVotingUserVotedDirection, isNull);
      expect(updated.postVotingHasVotes, isFalse);
      expect(updated.postVotingCommentsCount, 1);
      expect(updated.postVotingComments, same(post.postVotingComments));
    });

    test(
      'Topic and TopicDetail preserve post-voting state through parsing and copy',
      () {
        final topic = Topic.fromJson({'id': 77, 'is_post_voting': true});
        expect(topic.isPostVoting, isTrue);
        expect(topic.copyWith(unread: 2).isPostVoting, isTrue);

        final detail = TopicDetail.fromJson({
          'id': 77,
          'post_stream': {'posts': <dynamic>[], 'stream': <dynamic>[]},
          'is_post_voting': true,
        });
        expect(detail.isPostVoting, isTrue);
        expect(detail.copyWith(title: 'Updated').isPostVoting, isTrue);
        expect(detail.copyWith(isPostVoting: false).isPostVoting, isFalse);
      },
    );
  });
}
