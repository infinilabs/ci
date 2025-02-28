#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import re
import json
import yaml
import requests
import logging

class Yaml:

  def __init__(self, file_dir):
    self.file_dir = str(file_dir)

  def get_yaml_data(self) -> dict:
    with open(self.file_dir, 'r', encoding='utf-8') as f:
      return yaml.load(f.read(), Loader=yaml.FullLoader)

  def write_yaml_data(self, name: str, key: str, value) -> int:
    with open(self.file_dir, encoding='utf-8') as f:
      dict_temp = yaml.load(f, Loader=yaml.FullLoader)
      try:
        for p in dict_temp['list']:
          if p['key'] == name:
            p[key] = value
      except KeyError:
        if not dict_temp:
          dict_temp = {}
        dict_temp.update({'list': [{key: value}]})

    with open(self.file_dir, 'w', encoding='utf-8') as f:
      yaml.dump(dict_temp, f, allow_unicode=True)

class YamlUpdater:
    def __init__(self, file_dir):
        self.file_dir = file_dir

    def write_yaml_data(self, key, value):
        with open(self.file_dir, 'r', encoding='utf-8') as f:
           data = yaml.safe_load(f)

        if key in data:
             data[key]['version'] = value
        else: # 循环查找 key
            for k, v in data.items():
               if isinstance(v, dict) and key in v:
                   v['version'] = value
                   continue

        with open(self.file_dir, 'w', encoding='utf-8') as f:
          yaml.dump(data, f, default_flow_style=False)

# 配置日志记录
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 获取环境变量的值
latest_url = os.getenv('LATEST_URL')
code_base_path  = os.getenv('CODE_BASE_PATH')
build_version = os.getenv('VERSION')
build_number = os.getenv('BUILD_NUMBER')
build_date = os.getenv('BUILD_DATE')
product = os.getenv('PNAME')
product_vers = {}

download_data = Yaml(file_dir=f'{code_base_path}/publish/download.yaml')
quick_start_data = YamlUpdater(file_dir=f'{code_base_path}/publish/quick_start.yaml')

# 获取最新发布的版本信息
def get_tags():
  latest_vers = requests.get(latest_url, timeout=30).json()
  product_vers.update(latest_vers)
  print(json.dumps(product_vers, sort_keys=False, indent=4))

# 更新官网信息
def update_publish():
    for p in download_data.get_yaml_data()['list']:
        if p['key'] == product:
            print(f'{product} update {build_version}-{build_number} at {build_date}.')
            quick_start_data.write_yaml_data(product, f'{build_version}-{build_number}')
            if p['version'] != build_version or p['number'] != build_number:
                download_data.write_yaml_data(product, "version", build_version)
                download_data.write_yaml_data(product, "number", build_number)
                download_data.write_yaml_data(product, "build_date", build_date)

if __name__ == '__main__':

    # 记录获取到的环境变量值
  logger.info("Environment Variables:")
  logger.info(f"GITHUB_WORKSPACE: {code_base_path}")
  logger.info(f"VERSION: {build_version}")
  logger.info(f"BUILD_NUMBER: {build_number}")
  logger.info(f"BUILD_DATE: {build_date}")
  logger.info(f"PRODUCT: {product}")

  print('\nFetching latest publish tags...')
  get_tags()

  print('\nUpdating official website publish data...')
  update_publish()