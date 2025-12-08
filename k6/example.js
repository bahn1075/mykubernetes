// test.js
import http from "k6/http";
import { check } from "k6";
 
export const options = {
  scenarios: {
    scenarios_example: {
      executor: "per-vu-iterations",
      vus: 100,  //가상 사용자
      iterations: 100, //반복 횟수
      maxDuration: "10s", //timeout. 30초를 초과하면 테스트 종료하고 나머지는 drop으로 간주
    },
  },
};
export default function () {
  const params = {
    headers: {
      "Content-Type": "application/json",
    },
  };
  const response = http.get("http://192.168.49.100", { //테스트 대상 URL
    params,
  });
  check(response, { "status is 200": (r) => r.status === 200 }); //응답 코드가 200인지 확인
}