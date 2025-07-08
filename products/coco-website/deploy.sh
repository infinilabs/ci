#!/bin/bash

ls -lh /opt/coco-website.zip
unzip -q /opt/coco-website.zip -d /opt/coco-website
chown -R www-data:www-data /opt/coco-website