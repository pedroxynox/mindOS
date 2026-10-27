import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { createHttpHarness, TEST_USER_ID } from '../test/http-harness';
import { GraphController } from './graph.controller';
import { GraphService } from './graph.service';

/**
 * Graph corrections over HTTP (FR-2.4): real ValidationPipe + routing, the
 * service is a double. Checks status codes, DTO validation and that the
 * caller id always comes from the token.
 */
describe('GraphController (HTTP)', () => {
  let app: INestApplication;
  const NODE_ID = '33333333-3333-4333-8333-333333333333';
  const graph = {
    summary: jest.fn(),
    listNodes: jest.fn(),
    entity: jest.fn(async () => ({ id: NODE_ID, mentions: 2 })),
    rename: jest.fn(async () => ({ id: NODE_ID, title: 'Marcos', updated: 1 })),
    remove: jest.fn(async () => undefined),
    reviewEdge: jest.fn(async () => ({ id: NODE_ID, deleted: true })),
    captureEntities: jest.fn(),
  };

  beforeAll(async () => {
    app = await createHttpHarness(
      [GraphController],
      [
        { provide: GraphService, useValue: graph },
        { provide: JwtService, useValue: {} },
      ],
    );
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => jest.clearAllMocks());

  it('returns an entity by id', async () => {
    const res = await request(app.getHttpServer()).get(
      `/v1/graph/nodes/${NODE_ID}`,
    );
    expect(res.status).toBe(200);
    expect(graph.entity).toHaveBeenCalledWith(TEST_USER_ID, NODE_ID);
  });

  it('rejects a non-uuid node id', async () => {
    const res = await request(app.getHttpServer()).get('/v1/graph/nodes/abc');
    expect(res.status).toBe(400);
    expect(graph.entity).not.toHaveBeenCalled();
  });

  it('renames with a trimmed title and the default node scope', async () => {
    const res = await request(app.getHttpServer())
      .patch(`/v1/graph/nodes/${NODE_ID}`)
      .send({ title: '  Marcos  ' });
    expect(res.status).toBe(200);
    expect(graph.rename).toHaveBeenCalledWith(
      TEST_USER_ID,
      NODE_ID,
      'Marcos',
      'node',
    );
  });

  it('renames the whole entity with scope=entity', async () => {
    await request(app.getHttpServer())
      .patch(`/v1/graph/nodes/${NODE_ID}`)
      .send({ title: 'Marcos', scope: 'entity' })
      .expect(200);
    expect(graph.rename).toHaveBeenCalledWith(
      TEST_USER_ID,
      NODE_ID,
      'Marcos',
      'entity',
    );
  });

  it.each([
    [{ title: '   ' }],
    [{ title: 'x'.repeat(501) }],
    [{ title: 'Marcos', scope: 'all' }],
    [{ title: 'Marcos', user_id: TEST_USER_ID }],
    [{}],
  ])('rejects an invalid rename %j with 400', async (body) => {
    const res = await request(app.getHttpServer())
      .patch(`/v1/graph/nodes/${NODE_ID}`)
      .send(body);
    expect(res.status).toBe(400);
    expect(graph.rename).not.toHaveBeenCalled();
  });

  it('removes with 204, node scope by default', async () => {
    await request(app.getHttpServer())
      .delete(`/v1/graph/nodes/${NODE_ID}`)
      .expect(204);
    expect(graph.remove).toHaveBeenCalledWith(TEST_USER_ID, NODE_ID, 'node');

    await request(app.getHttpServer())
      .delete(`/v1/graph/nodes/${NODE_ID}?scope=entity`)
      .expect(204);
    expect(graph.remove).toHaveBeenLastCalledWith(
      TEST_USER_ID,
      NODE_ID,
      'entity',
    );
  });

  it('rejects an unknown delete scope', async () => {
    await request(app.getHttpServer())
      .delete(`/v1/graph/nodes/${NODE_ID}?scope=everything`)
      .expect(400);
    expect(graph.remove).not.toHaveBeenCalled();
  });

  it('reviews a connection with a boolean only', async () => {
    await request(app.getHttpServer())
      .patch(`/v1/graph/edges/${NODE_ID}`)
      .send({ confirmed: false })
      .expect(200);
    expect(graph.reviewEdge).toHaveBeenCalledWith(TEST_USER_ID, NODE_ID, false);

    await request(app.getHttpServer())
      .patch(`/v1/graph/edges/${NODE_ID}`)
      .send({ confirmed: 'yes' })
      .expect(400);
    expect(graph.reviewEdge).toHaveBeenCalledTimes(1);
  });
});
