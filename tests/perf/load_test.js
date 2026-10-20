import http from 'k6/http';
import { check, sleep } from 'k6';

// 性能测试基线配置 (10 个并发用户持续 15 秒)
export const options = {
  stages: [
    { duration: '5s', target: 10 },
    { duration: '10s', target: 10 },
    { duration: '2s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% 请求必须在 500ms 内完成
  },
};

export default function () {
  // 对 Mock 服务执行接口并发压测
  const res = http.get('http://qa-mock-service:4010/api/v1/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'health status is UP': (r) => JSON.parse(r.body).status === 'UP',
  });
  sleep(1);
}
