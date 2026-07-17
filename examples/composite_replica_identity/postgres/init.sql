CREATE TABLE IF NOT EXISTS memberships (
  tenant_id bigint NOT NULL,
  member_uuid text NOT NULL,
  status text NOT NULL,
  PRIMARY KEY (tenant_id, member_uuid)
);

CREATE PUBLICATION mammoth_publication FOR TABLE memberships;
