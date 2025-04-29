// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MovieChecksum {
    // Mapping để lưu trữ checksum của các phim
    mapping(string => string) private movieChecksums;

    // Sự kiện để thông báo khi một checksum mới được thêm vào
    event MovieChecksumAdded(string movieName, string checksum);

    // Hàm để thêm checksum của video vào blockchain
    function addMovieChecksum(string memory movieName, string memory checksum) public {
        // Lưu trữ checksum cho movieName
        movieChecksums[movieName] = checksum;

        // Emit sự kiện
        emit MovieChecksumAdded(movieName, checksum);
    }

    // Hàm để lấy checksum của một video (nếu có)
    function getMovieChecksum(string memory movieName) public view returns (string memory) {
        return movieChecksums[movieName];
    }
}
