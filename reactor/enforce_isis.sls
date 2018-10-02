{% set body_json = data['body']|load_json %}
{% set devicename = body_json['status']['entityId'] %}

enforce_isis_overload:
  local.state.apply:
    - tgt: "{{ devicename }}"
    - arg:
      - isis
