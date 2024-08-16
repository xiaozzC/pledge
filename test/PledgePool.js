const { expect, use } = require("chai");
const { ethers } = require("hardhat");
const { solidity } = require("ethereum-waffle");

(async () => {
    const chaiAsPromised = await import('chai-as-promised'); // 动态加载 ES 模块

    // 使用插件
    use(solidity);
    use(chaiAsPromised.default);

    describe("PledgePool Contract", function () {
        let PledgePool;
        let pledgePool;
        let owner;
        let addr1;
        let addr2;
        let feeAddress;
        let multiSignature;
        let currentTime;

        beforeEach(async function () {
            console.log("Deploying contract...");
            // 部署合约
            PledgePool = await ethers.getContractFactory("PledgePool");
            [owner, addr1, addr2, _] = await ethers.getSigners();
            feeAddress = addr1.address;
            multiSignature = addr2.address;

            pledgePool = await PledgePool.deploy(
                owner.address,
                addr1.address,
                feeAddress,
                multiSignature
            );

            await pledgePool.deployed();

            currentTime = (await ethers.provider.getBlock('latest')).timestamp;
        });

        it("Should set the lending and borrowing fees with valid multi-signature", async function () {
            console.log("Running test for setting fees...");
            const lendFee = 100;
            const borrowFee = 200;

            const signature1 = await owner.signMessage("SomeMessage");
            const signature2 = await addr2.signMessage("SomeMessage");

            await expect(pledgePool.setFee(lendFee, borrowFee, [signature1, signature2]))
                .to.emit(pledgePool, "SetFee")
                .withArgs(lendFee, borrowFee);
        });

        it("Should revert if invalid multi-signature is provided", async function () {
            console.log("Running test for invalid multi-signature...");
            const lendFee = 100;
            const borrowFee = 200;

            const invalidSignature = await addr1.signMessage("InvalidMessage");

            await expect(pledgePool.setFee(lendFee, borrowFee, [invalidSignature]))
                .to.be.revertedWith("Multi-signature check failed");
        });

        describe("createPoolInfo", function () {
            it("Should create pool info with valid parameters", async function () {
                console.log("Running create pool info test...");
                const settleTime = currentTime + 3600; // 1小时后
                const endTime = currentTime + 7200; // 2小时后
                const interestRate = 5000; // 5%
                const maxSupply = ethers.utils.parseEther("1000");
                const martgageRate = 1000; // 10%
                const lendToken = addr1.address;
                const borrowToken = addr2.address;
                const spToken = addr1.address;
                const jpToken = addr2.address;
                const autoLiquidateThreshold = ethers.utils.parseEther("10");

                await pledgePool.createPoolInfo(
                    settleTime,
                    endTime,
                    interestRate,
                    maxSupply,
                    martgageRate,
                    lendToken,
                    borrowToken,
                    spToken,
                    jpToken,
                    autoLiquidateThreshold
                );

                // 检查创建的资金池信息
                const poolBaseInfo = await pledgePool.poolBaseInfo(0);
                const poolDataInfo = await pledgePool.poolDataInfo(0);

                expect(poolBaseInfo.settleTime).to.equal(settleTime);
                expect(poolBaseInfo.endTime).to.equal(endTime);
                expect(poolBaseInfo.interestRate).to.equal(interestRate);
                expect(poolBaseInfo.maxSupply).to.equal(maxSupply);
                expect(poolBaseInfo.martgageRate).to.equal(martgageRate);
                expect(poolBaseInfo.lendToken).to.equal(lendToken);
                expect(poolBaseInfo.borrowToken).to.equal(borrowToken);
                expect(poolBaseInfo.spCoin).to.equal(spToken);
                expect(poolBaseInfo.jpCoin).to.equal(jpToken);
                expect(poolBaseInfo.autoLiquidateThreshold).to.equal(autoLiquidateThreshold);

                expect(poolDataInfo.settleAmountLend).to.equal(0);
                expect(poolDataInfo.settleAmountBorrow).to.equal(0);
                expect(poolDataInfo.finishAmountLend).to.equal(0);
                expect(poolDataInfo.finishAmountBorrow).to.equal(0);
                expect(poolDataInfo.liquidationAmounLend).to.equal(0);
                expect(poolDataInfo.liquidationAmounBorrow).to.equal(0);
            });

            it("Should revert if end time is not greater than settle time", async function () {
                const settleTime = currentTime + 3600; // 1小时后
                const endTime = currentTime + 1800; // 30分钟后 (不合法)

                await expect(
                    pledgePool.createPoolInfo(
                        settleTime,
                        endTime,
                        5000,
                        ethers.utils.parseEther("1000"),
                        1000,
                        addr1.address,
                        addr2.address,
                        addr1.address,
                        addr2.address,
                        ethers.utils.parseEther("10")
                    )
                ).to.be.revertedWith("createPool:end time grate than settle time");
            });

            it("Should revert if token addresses are zero", async function () {
                const settleTime = currentTime + 3600;
                const endTime = currentTime + 7200;

                await expect(
                    pledgePool.createPoolInfo(
                        settleTime,
                        endTime,
                        5000,
                        ethers.utils.parseEther("1000"),
                        1000,
                        addr1.address,
                        addr2.address,
                        ethers.constants.AddressZero,
                        addr2.address,
                        ethers.utils.parseEther("10")
                    )
                ).to.be.revertedWith("createPool:is zero address");

                await expect(
                    pledgePool.createPoolInfo(
                        settleTime,
                        endTime,
                        5000,
                        ethers.utils.parseEther("1000"),
                        1000,
                        addr1.address,
                        addr2.address,
                        addr1.address,
                        ethers.constants.AddressZero,
                        ethers.utils.parseEther("10")
                    )
                ).to.be.revertedWith("createPool:is zero address");
            });
        });
    });
})();
