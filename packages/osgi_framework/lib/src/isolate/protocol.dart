/// What a bundle in another isolate says to the framework, and hears back.
///
/// Every message here is sendable over a `SendPort`, and everything that
/// crosses is either a port, an int, a string, or a map the sender treats as
/// immutable. Nothing crosses that would have to be copied to be useful.
///
/// ## Why services cross as ports
///
/// Objects sent between isolates are copied -- verified, not assumed: a list
/// mutated by the receiver leaves the sender's list untouched. A service object
/// sent this way would give the consumer a *copy*, which is not a service at
/// all: calls on it would never reach the bundle that published it.
///
/// So what the registry holds for a remote bundle is a [ServiceEndpoint]: the
/// port its owner listens on, plus the properties needed to find it. The
/// message protocol a service speaks on that port belongs to the service, not
/// to this framework.
///
/// A `const` map, by contrast, arrives identical rather than copied, which is
/// why service properties are best declared `const`.
library;

import 'dart:isolate';

import '../event.dart';

/// A service, as seen from outside the isolate that owns it.
///
/// [port] is where its owner listens. [serviceId] is assigned by the framework
/// and is how a registration is named later, since the endpoint itself cannot
/// be compared by identity once it has crossed an isolate boundary.
class ServiceEndpoint {
  const ServiceEndpoint({
    required this.serviceId,
    required this.interfaceName,
    required this.port,
    required this.properties,
  });

  final int serviceId;
  final String interfaceName;
  final SendPort port;
  final Map<String, Object?> properties;

  @override
  bool operator ==(Object other) =>
      other is ServiceEndpoint && other.serviceId == serviceId;

  @override
  int get hashCode => serviceId.hashCode;

  @override
  String toString() => 'ServiceEndpoint($serviceId, $interfaceName)';
}

/// A request from a bundle isolate to the framework isolate.
///
/// [id] pairs a request with its [FrameworkReply]; [replyTo] is where that
/// reply and any later tracker events for this bundle are delivered.
sealed class FrameworkRequest {
  const FrameworkRequest({
    required this.id,
    required this.bundle,
    required this.replyTo,
  });

  final int id;
  final String bundle;
  final SendPort replyTo;
}

/// Announce a bundle and the port it receives on, so other bundles can reach
/// it and so the framework can clean up after it.
class AttachBundle extends FrameworkRequest {
  const AttachBundle({
    required super.id,
    required super.bundle,
    required super.replyTo,
  });
}

/// Release everything the bundle holds: its services, its trackers, and its
/// place in the routing table. Sent when the bundle stops.
class DetachBundle extends FrameworkRequest {
  const DetachBundle({
    required super.id,
    required super.bundle,
    required super.replyTo,
  });
}

/// Publish [port] as a service under [interfaceName].
class RegisterEndpoint extends FrameworkRequest {
  const RegisterEndpoint({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.interfaceName,
    required this.port,
    required this.properties,
  });

  final String interfaceName;
  final SendPort port;
  final Map<String, Object?> properties;
}

/// Withdraw a service published earlier by this bundle.
class UnregisterEndpoint extends FrameworkRequest {
  const UnregisterEndpoint({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.serviceId,
  });

  final int serviceId;
}

/// Ask for services under [interfaceName], optionally narrowed by an LDAP
/// [filter]. [all] asks for every match rather than the highest-ranked one.
class LookupEndpoints extends FrameworkRequest {
  const LookupEndpoints({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.interfaceName,
    required this.all,
    this.filter,
  });

  final String interfaceName;
  final bool all;
  final String? filter;
}

/// Start watching [interfaceName]. Matching services are delivered as
/// [TrackerEvent]s, beginning with those already registered.
class OpenTracker extends FrameworkRequest {
  const OpenTracker({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.trackerId,
    required this.interfaceName,
    this.filter,
  });

  final int trackerId;
  final String interfaceName;
  final String? filter;
}

/// Stop watching.
class CloseTracker extends FrameworkRequest {
  const CloseTracker({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.trackerId,
  });

  final int trackerId;
}

/// Route [message] to another bundle's receive port.
///
/// The framework routes; it does not inspect. A large payload should travel as
/// a `Pointer` address in an int rather than as a copied object.
class SendToBundle extends FrameworkRequest {
  const SendToBundle({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.target,
    required this.message,
  });

  final String target;
  final Object? message;
}

/// The framework's answer to a [FrameworkRequest] with the same [id].
sealed class FrameworkReply {
  const FrameworkReply(this.id);

  final int id;
}

/// The request succeeded and carried nothing back.
class Acknowledged extends FrameworkReply {
  const Acknowledged(super.id);
}

/// A service was published; [serviceId] names it for later withdrawal.
class EndpointRegistered extends FrameworkReply {
  const EndpointRegistered(super.id, this.serviceId);

  final int serviceId;
}

/// The result of a [LookupEndpoints], highest-ranked first. Empty when nothing
/// matched.
class EndpointsFound extends FrameworkReply {
  const EndpointsFound(super.id, this.endpoints);

  final List<ServiceEndpoint> endpoints;
}

/// The request could not be served. [message] says why.
///
/// A malformed filter and an unknown target bundle both arrive this way: the
/// framework does not throw into another isolate.
class RequestFailed extends FrameworkReply {
  const RequestFailed(super.id, this.message);

  final String message;
}

/// A service appeared or went away, for a tracker the bundle opened.
///
/// Not a reply: it carries a [trackerId] rather than a request id, and arrives
/// whenever the registry changes.
class TrackerEvent {
  const TrackerEvent({
    required this.trackerId,
    required this.added,
    required this.endpoint,
  });

  final int trackerId;

  /// True when the service appeared, false when it went away.
  final bool added;

  final ServiceEndpoint endpoint;
}

/// Publish an event to every bundle subscribed to its topic.
///
/// Unlike a service, an event is a value: copying it across an isolate
/// boundary is what delivery *means*, not a thing to avoid. No reply comes
/// back -- posting is asynchronous, and an acknowledgement per event would put
/// a round trip on a path meant to carry many.
class PostEvent extends FrameworkRequest {
  const PostEvent({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.event,
  });

  final Event event;
}

/// Start receiving events whose topic matches [topicPattern].
///
/// Matches arrive as [EventDelivered] carrying [subscriptionId].
class SubscribeTopic extends FrameworkRequest {
  const SubscribeTopic({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.subscriptionId,
    required this.topicPattern,
  });

  final int subscriptionId;
  final String topicPattern;
}

/// Stop receiving events for one subscription.
class UnsubscribeTopic extends FrameworkRequest {
  const UnsubscribeTopic({
    required super.id,
    required super.bundle,
    required super.replyTo,
    required this.subscriptionId,
  });

  final int subscriptionId;
}

/// An event matching a subscription the bundle opened.
///
/// Not a reply: it carries a [subscriptionId] rather than a request id, and
/// arrives whenever someone posts a matching topic.
class EventDelivered {
  const EventDelivered({required this.subscriptionId, required this.event});

  final int subscriptionId;
  final Event event;
}
