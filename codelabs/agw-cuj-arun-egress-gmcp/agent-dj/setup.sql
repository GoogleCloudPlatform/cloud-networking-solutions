-- Create the BigQuery dataset schema first if it does not exist
CREATE SCHEMA IF NOT EXISTS `dj_ds`;

-- Create or replace the Disk Jockeys database table
CREATE OR REPLACE TABLE `dj_ds.disk_jockeys` (
  name STRING,
  phone STRING,
  credit_card STRING
);

-- Ingest mock data
INSERT INTO `dj_ds.disk_jockeys` (name, phone, credit_card) VALUES
('DJ Shadow', '555-0101', '1111-2222-3333-4444'),
('DJ Spooky', '555-0102', '2222-3333-4444-5555'),
('DJ Premier', '555-0103', '3333-4444-5555-6666'),
('DJ Jazzy Jeff', '555-0104', '4444-5555-6666-7777'),
('DJ Screw', '555-0105', '5555-6666-7777-8888'),
('DJ Khaled', '555-0106', '6666-7777-8888-9999'),
('DJ Snake', '377-5432', '7777-8888-9999-0000'),
('DJ Tiësto', '555-0108', '8888-9999-0000-1111'),
('DJ Calvin Harris', '555-0109', '9999-0000-1111-2222'),
('DJ Marshmello', '555-0110', '0000-1111-2222-3333'),
('DJ Cosmopup', '123-4567', '1111-1111-1111-1111'),
('DJ Fishfry', '123-9876', '4444-4444-4444-4444');