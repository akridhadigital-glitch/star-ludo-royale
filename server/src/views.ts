import type { Room } from './rooms/roomManager.js';

/** What clients see. Never includes anything beyond public profile data. */
export function roomView(room: Room) {
  return {
    code: room.code,
    hostId: room.hostId,
    maxPlayers: room.maxPlayers,
    status: room.status,
    members: room.members.map(m => ({
      userId: m.userId, name: m.name, avatar: m.avatar, color: m.color, connected: m.connected, left: m.left,
      away: m.missed >= 1, missed: m.missed,
    })),
    game: room.game,
    deadline: room.deadline,
    result: room.result,
  };
}
export type RoomViewDto = ReturnType<typeof roomView>;
