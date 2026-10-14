local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'DemonHunter-Havoc','Druid-Balance','DeathKnight-Blood','Mage-Arcane','Mage-Frost','Unknown-Unknown','Warrior-Protection','Shaman-Enhancement','Shaman-Elemental','Evoker-Devastation','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','Paladin-Retribution','Druid-Guardian','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Hunter-BeastMastery','Priest-Shadow','Rogue-Outlaw','Rogue-Assassination','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Devourer','Druid-Restoration','Paladin-Protection','Hunter-Survival','Evoker-Augmentation','Monk-Brewmaster',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adroc:BAAANQAECgQIBAAAAA==.',
Ah='Ahpuch:BAABNQAECn8tAAIBAAkKJxpNFgDmAgABAAkKJxpNFgDmAgAAAA==.',
Ai='Aidasul:BAAANQAECgYIEwAAAA==.',
Al='Alarin:BAAANQADCgcIBwAAAA==.Aldesca:BAAANQAECgYIEgAAAA==.Allarie:BAAANQADCggICAAAAA==.',
Am='Amarilli:BAAANQADCgUICAABNQAECgkJLAACAA8bAA==.',
An='Ancile:BAAANQAECgUIBwAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgcIDgAAAA==.',
Ar='Armstrõng:BAAANQAECgQIBQAAAA==.',
As='Ashaxxi:BAABNQAFFH8JAAIDAAQKngf8FwDhAAADAAQKngf8FwDhAAAAAA==.Ashpaw:BAAANQAECgcIEwABNQAFFAQICQADAJ4HAA==.Aspen:BAAANQAECgEIAQAAAA==.',
At='Atcjedi:BAAANQAECgQIBgAAAA==.Atmospherewr:BAAANQAFFAEIAQABNQAFFAcIHwAEANIlAA==.Atmospherez:BAACNQAFFH8fAAMEAAcK0iXVBgBQAgAEAAYKsCXVBgBQAgAFAAEKWybcCQBxAAA1AAQKfyMAAgQACQobJhQeAGADAAQACQobJhQeAGADAAAA.',
Au='Aurzon:BAAANQADCgUIBQABNQADCgcIDgAGAAAAAA==.',
Av='Avaniah:BAABNQAECn8cAAIHAAcKcB83DQBcAgAHAAcKcB83DQBcAgAAAA==.',
Az='Azmodan:BAAANQADCgcIBwAAAA==.Azraelor:BAACNQAFFH8IAAMIAAQKSBg6BAAGAQAIAAMKSBg6BAAGAQAJAAEKAADdLgBMAAA1AAQKfz4AAwgACQoTJLsDAF0DAAgACQoTJLsDAF0DAAkACQqRGktKAEoCAAAA.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQAECgUIBQAAAA==.Badhealz:BAAANQADCgcIBwAAAA==.Baep:BAAANQAECgUICQAAAA==.Bandrago:BAABNQAECn8lAAIKAAcKigqlHgBmAQAKAAcKigqlHgBmAQAAAA==.Barracuda:BAAANQAECgMIAwAAAA==.Batmeng:BAAANQAECgYIAwAAAA==.',
Bb='Bbirog:BAAANQAECggICQABNQAECgkJFgALAC0cAA==.',
Be='Bearione:BAAANQAECggIAQAAAA==.Beaulioh:BAABNQAECn8WAAILAAkKLRx3MACjAgALAAkKLRx3MACjAgAAAA==.Bekzarn:BAAANQAECgEIAQABNQAECgYIEgAGAAAAAA==.Belegmor:BAAANQAECgIIAgABNQAECgYIEwAGAAAAAA==.Benfrank:BAABNQAECn8gAAICAAgKoxYRPgAEAgACAAgKoxYRPgAEAgAAAA==.Bernthul:BAAANQAECgcIDgAAAA==.Bethan:BAAANQAECgYIEQAAAA==.',
Bl='Blaart:BAABNQAECn8eAAQMAAgKsRbFhADVAQAMAAcKyhXFhADVAQANAAIKrxZWUgCGAAAOAAEKAADKMgAtAAAAAA==.Blackwaters:BAABNQAECn8kAAMIAAgKZSWuBABFAwAIAAgKZSWuBABFAwAJAAUKdxXdqQA8AQAAAA==.Blax:BAABNQAECn8cAAMPAAgKXhnDDADqAQAPAAYK/hvDDADqAQAQAAYK2BJZxwBkAQAAAA==.Blindcow:BAABNQAECn8sAAIQAAkKyh4iOADhAgAQAAkKyh4iOADhAgAAAA==.Blindhugs:BAABNQAECn8YAAMBAAgKwRGONgD3AQABAAgKdBGONgD3AQARAAQKDgVCJgCCAAAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgYIBQAAAA==.Blùey:BAAANQADCgYIBgABNQAECgkJKQASALggAA==.',
Bo='Bodytypebig:BAABNQAECn81AAITAAkK+xrICwCpAgATAAkK+xrICwCpAgAAAA==.Boicrystian:BAAANQAECgUICwAAAA==.Bolillo:BAAANQADCgcIDAABNQAECgkJFgALAC0cAA==.Bomie:BAAANQADCgUIBQAAAA==.Bookitty:BAAANQADCggIGAAAAA==.Boosty:BAABNQAECn8sAAIQAAgKCiC2QQDCAgAQAAgKCiC2QQDCAgAAAA==.Bossladie:BAAANQAECgQIBQAAAA==.Bossladìe:BAABNQAECn8vAAIUAAkKfBgILwCoAgAUAAkKfBgILwCoAgAAAA==.Boston:BAAANQAECgIIAwAAAA==.',
Br='Brenagain:BAAANQAECgQIBAAAAA==.Brewholic:BAABNQAECn8eAAIVAAgKiiNqBwAaAwAVAAgKiiNqBwAaAwAAAA==.Brip:BAAANQAECggICAAAAA==.Bristle:BAABNQAECn8vAAMJAAkKhyAuGAA1AwAJAAkKhyAuGAA1AwAIAAMKABs3KADZAAAAAA==.Brommix:BAAANQADCgMIBgAAAA==.Brotem:BAAANQAECggIBwAAAA==.Broxy:BAAANQAECgEIAQAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDgAAAA==.Bullshiitake:BAABNQAECn8WAAIUAAgK+w7IcwC5AQAUAAgK+w7IcwC5AQAAAA==.',
['Bö']='Bönezone:BAAANQADCgQIBAAAAA==.',
Ca='Calaglin:BAABNQAECn8bAAQMAAgKDxXWjQC/AQAMAAcKuhPWjQC/AQANAAEKvBuvaQBMAAAOAAEKsgF0NgAWAAAAAA==.Calelorian:BAAANQADCgYIFAAAAA==.Catstack:BAAANQAECgEIAQAAAA==.',
Ce='Celdiirn:BAAANQADCggIJwAAAA==.Celesti:BAABNQAECn8cAAISAAYKvBJp4ABUAQASAAYKvBJp4ABUAQAAAA==.',
Ch='Chaos:BAAANQAECgUIBQABNQAECgQIBgAGAAAAAA==.Chiky:BAAANQAECgIIAwAAAA==.Choom:BAAANQAECgYIEAAAAA==.Chubsy:BAAANQAECggIEAAAAA==.Chuckkyd:BAABNQAECn8kAAISAAgKjBFXjAAIAgASAAgKjBFXjAAIAgAAAA==.',
Cl='Claugh:BAABNQAECn8YAAMWAAkK5hmeKwA8AgAWAAkK5hmeKwA8AgAXAAEKTRRQ2AA6AAAAAA==.Cleb:BAABNQAECn8YAAMSAAkKhSbcAQDzAwASAAkKhSbcAQDzAwAUAAIKeR4Y6ACsAAAAAA==.Clocker:BAABNQAECn8ZAAIYAAgK4Qu8gACGAQAYAAgK4Qu8gACGAQAAAA==.Clumbsykoala:BAABNQAECn8bAAICAAcKvw49UQCTAQACAAcKvw49UQCTAQAAAA==.',
Co='Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAACNQAFFH8WAAIZAAgK4RPcAQCmAgAZAAgK4RPcAQCmAgA1AAQKfygAAhkACQq3GkYOAMICABkACQq3GkYOAMICAAAA.Combatcow:BAABNQAECn8dAAIPAAgKHyLrBADdAgAPAAgKHyLrBADdAgAAAA==.Contagion:BAAANQAECggIEAAAAA==.Coorona:BAAANQADCgcIEwAAAA==.Cozmic:BAABNQAECn8pAAMEAAkKsiFoSwDrAgAEAAgKFSFoSwDrAgAFAAMKzSLmGwAOAQAAAA==.',
Cr='Craftymidget:BAAANQAECgcIBwAAAA==.Crucifixd:BAAANQAECgEIAQAAAA==.Cryptonic:BAAANQAECggICAAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAABNQAECn8sAAIQAAgKTCAGOQDeAgAQAAgKTCAGOQDeAgAAAA==.',
Cu='Curandero:BAABNQAECn8XAAIJAAQKvBE90ADuAAAJAAQKvBE90ADuAAAAAA==.Curie:BAAANQAECgEIAQABNQAECggIMgAaAH8cAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUIBQAAAA==.Dameck:BAABNQAECn8uAAIQAAkKiBbyXgBtAgAQAAkKiBbyXgBtAgAAAA==.Dankula:BAAANQABCgQIAQAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCggICgABNQAECggIHQAXAH4bAA==.Dasdots:BAAANQAECgcIEwAAAA==.Dasmuro:BAAANQADCgIIAgABNQAECgYIHwADAOYFAA==.Davy:BAAANQADCgYIBgAAAA==.Dazzeler:BAABNQAECn8dAAIXAAgKfhsjMABsAgAXAAgKfhsjMABsAgAAAA==.',
De='Deadeenside:BAAANQAECgQIBAABNQAECggIHAASAFsWAA==.Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAABNQAECn8bAAIbAAcK8xFQkwDeAQAbAAcK8xFQkwDeAQAAAA==.Delver:BAAANQAECgQICQAAAA==.Demongirly:BAAANQADCgQIBAAAAA==.Demonsue:BAAANQABCgIIAgAAAA==.Demorlize:BAAANQADCgQIBAABNQAECgYIEQAGAAAAAA==.Denathria:BAABNQAECn8bAAMUAAkK0x6wFwAbAwAUAAkK0x6wFwAbAwASAAEKYRJ0jQFBAAAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAACNQAFFH8aAAMcAAcKARl2AgBhAgAcAAcKARl2AgBhAgALAAIKPQUjJACvAAA1AAQKfyYAAhwACQrWI5oIAFEDABwACQrWI5oIAFEDAAAA.Deviourer:BAAANQABCgIIAgAAAA==.Devo:BAAANQABCgIIAgAAAA==.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.Difflect:BAAANQADCgYIBgABNQADCggIEAAGAAAAAA==.Diio:BAAANQADCggICAAAAA==.',
Do='Doak:BAABNQAECn8yAAQaAAgKfxznDgCJAgAaAAgKfxznDgCJAgAdAAQK8whWEwDIAAAeAAIKigkgjQBxAAAAAA==.Doonfist:BAAANQABCggIEwAAAA==.Dotz:BAACNQAFFH8HAAMNAAMKAxZlCwCkAAANAAIKbhdlCwCkAAAMAAEKLxPpPgBMAAA1AAQKfyEAAw0ACQp0Hs0kAEsBAAwABwpKHmhsABUCAA0ABgq5EM0kAEsBAAAA.Douchec:BAAANQAECgUIBgAAAA==.',
Dr='Draconius:BAAANQADCgYIFQAAAA==.Draenor:BAAANQAECgMIBQAAAA==.Dragondilly:BAAANQAECgMIAwAAAA==.Dragonette:BAAANQAECgQIBAABNQAECggIJAAMAAwaAA==.Dragonforce:BAABNQAECn8eAAIKAAcKNBlvFAADAgAKAAcKNBlvFAADAgAAAA==.Dragonhaze:BAABNQAECn8ZAAIEAAYKGR6augANAgAEAAYKGR6augANAgAAAA==.Dragonskull:BAAANQAECgYJBgAAAA==.Drawkcab:BAAANQAFFAMIAwAAAA==.Drazentar:BAABNQAECn8fAAIDAAYK5gVWhQDkAAADAAYK5gVWhQDkAAAAAA==.Dream:BAAANQADCgUICQABNQAECggIHAAYAD0VAA==.Drevox:BAABNQAECn8pAAIXAAgKnRnPPAAqAgAXAAgKnRnPPAAqAgAAAA==.Druiddruid:BAAANQADCgYICQAAAA==.',
Du='Dulgar:BAABNQAECn8vAAMYAAkKmhpJLgCmAgAYAAkKmhpJLgCmAgAJAAEKdw71KAE8AAAAAA==.Dumami:BAAANQAECgEJAQABNQAECgYIAwAGAAAAAA==.',
['Dë']='Dëlilah:BAAANQAECgYICAAAAA==.',
Ea='Eaglewarrior:BAAANQADCggIDgAAAA==.Eatmydisc:BAAANQAECgQIBAAAAA==.',
Ec='Eclipselock:BAAANQAECggICgABNQAFFAYIGAABAGUYAA==.',
Eg='Egwaine:BAAANQAECgUIBQABNQAECgkJLAACAA8bAA==.',
El='Elind:BAAANQAECgQIBQAAAA==.Elisyum:BAAANQAECgIIAgAAAA==.Elleduff:BAABNQAECn8ZAAIfAAcK2QkpOQBFAQAfAAcK2QkpOQBFAQAAAA==.Eloragon:BAAANQABCgMIAwAAAA==.Elupally:BAAANQABCgIIAgABNQAECgYIAwAGAAAAAA==.Elyssabeta:BAAANQADCgQJBAAAAA==.Elysstaa:BAABNQAECn8vAAMLAAkKtxlwNgCLAgALAAkKtxlwNgCLAgAcAAYK0REJNgBvAQAAAA==.',
En='Endeavor:BAAANQAECgQIBAABNQAECgkJGAAXABodAA==.Entïty:BAAANQAECgEIAQABNQAECgUIEAAGAAAAAA==.',
Eo='Eogden:BAAANQAECgYICgAAAA==.',
Eq='Equilibria:BAABNQAECn8bAAIcAAcKvht7IQAnAgAcAAcKvht7IQAnAgAAAA==.',
Er='Erida:BAAANQAECgIJAgAAAA==.Ers:BAAANQADCgYIBgABNQAECgcIGQAQAAgiAA==.',
Es='Eskuf:BAAANQADCgMIAwAAAA==.',
Et='Etienne:BAAANQADCgEIAQAAAA==.Etík:BAAANQAECgUICAAAAA==.',
Ev='Evocative:BAACNQAFFH8FAAIKAAIKwheDCwCSAAAKAAIKwheDCwCSAAA1AAQKfxwAAgoACQp6Ha4KAL8CAAoACQp6Ha4KAL8CAAAA.',
Ex='Exaltso:BAAANQADCgYIDwAAAA==.',
Ey='Eyebright:BAAANQAFFAEIAQAAAA==.Eyye:BAAANQADCgQIBgABNQAECgYIDQAGAAAAAA==.',
Fa='Farns:BAACNQAFFH8QAAMFAAYK9R37AgDyAAAEAAUK3hzjFwCzAQAFAAMK2Rj7AgDyAAA1AAQKfycAAwQACQpbJQ4XAHcDAAQACQr9JA4XAHcDAAUABgq1JdMIAEoCAAAA.Fawndolynn:BAAANQAECgUIDAAAAA==.',
Fe='Felinepriest:BAAANQAECgYIEgAAAA==.Felovan:BAAANQAECgEIAQAAAA==.Felsoaked:BAAANQAECgIIAwAAAA==.Felstehr:BAABNQAECn8aAAIMAAcKPgv1mgCeAQAMAAcKPgv1mgCeAQAAAA==.Feltotes:BAAANQAECgQIBAAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAABNQAECn8aAAIYAAkKbSDbHAD4AgAYAAkKbSDbHAD4AgAAAA==.Firebäne:BAABNQAECn8dAAINAAkKOxxDAwAUAwANAAkKOxxDAwAUAwAAAA==.Fistnor:BAAANQAECgEIAQAAAA==.',
Fl='Flaminghawk:BAACNQAFFH8PAAIEAAYKKhjUDwDzAQAEAAYKKhjUDwDzAQA1AAQKfyEAAwUABwr4IlYZACkBAAQABwq5ItaUAFYCAAUAAwrjIVYZACkBAAAA.',
Fr='Franklin:BAAANQAECgcICQAAAA==.Frankotronic:BAABNQAECn8iAAIEAAkKvhaajABlAgAEAAkKvhaajABlAgAAAA==.Fraynetrain:BAAANQAECgQIBAABNQAECgYIDwAGAAAAAA==.Frayniac:BAAANQAECgYIDwAAAA==.Freakies:BAAANQADCgQIBgAAAA==.Freightfrayn:BAAANQAECgEIAQAAAA==.Freyin:BAABNQAECn8uAAIbAAkKMxrhLADlAgAbAAkKMxrhLADlAgAAAA==.Fridays:BAAANQADCgEIAQAAAA==.Frie:BAAANQADCgYIBgAAAA==.Frolgar:BAAANQADCgYICAAAAA==.Frostyflakez:BAAANQAECgEJAQAAAA==.',
Fu='Fullclangg:BAACNQAFFH8HAAIUAAMKviS5EQA/AQAUAAMKviS5EQA/AQA1AAQKfxgAAhQACAp3HZA0AI8CABQACAp3HZA0AI8CAAE1AAUUCAgkABkAcRsA.Fulldracarys:BAACNQAFFH8kAAIZAAgKcRuJAQC9AgAZAAgKcRuJAQC9AgA1AAQKfycAAhkACQrPIt8HACcDABkACQrPIt8HACcDAAAA.Fullgabagool:BAABNQAECn8eAAILAAkKeB3+IwDaAgALAAkKeB3+IwDaAgABNQAFFAgIJAAZAHEbAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAgIJAAZAHEbAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCggIGQAAAA==.Ganster:BAAANQAECgQIBQAAAA==.Gaya:BAAANQADCgYIEAAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAABNQAFFH8NAAIQAAUKAQepGgA5AQAQAAUKAQepGgA5AQAAAA==.',
Gi='Ginyeng:BAABNQAFFH8HAAMJAAQKxA3TGgDnAAAJAAMKxA3TGgDnAAAYAAIKZQKZJAB3AAAAAA==.',
Gl='Glimpse:BAABNQAECn8eAAIFAAkKUyNZAQCEAwAFAAkKUyNZAQCEAwAAAA==.',
Gn='Gnomebody:BAAANQAECgIIAwAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBgAAAA==.',
Gr='Greenmonsta:BAAANQADCgUIBQAAAA==.Grimknight:BAABNQAECn81AAISAAkKOyYEBADaAwASAAkKOyYEBADaAwAAAA==.Groovi:BAAANQADCgUIBQAAAA==.',
Gu='Guycow:BAABNQAECn8cAAIUAAkK9R4vHQD8AgAUAAkK9R4vHQD8AgAAAA==.',
Ha='Haldur:BAAANQABCgIIAgAAAA==.Hambonë:BAACNQAFFH8ZAAICAAcKEiDwAgCYAgACAAcKEiDwAgCYAgA1AAQKfygAAgIACQqMJt8CAM8DAAIACQqMJt8CAM8DAAAA.Hardballs:BAAANQAECgEIAQAAAA==.Hashbrowns:BAABNQAECn8vAAISAAkKsiUHCAC6AwASAAkKsiUHCAC6AwAAAA==.Havdk:BAAANQAECgIIAwAAAA==.Haxxorwyn:BAAANQAECgcIDQAAAA==.Hazreil:BAABNQAECn8vAAITAAkKrxo4CwC2AgATAAkKrxo4CwC2AgAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIEQAAAA==.Heavenlee:BAABNQAECn8cAAILAAcKNAoZlQBRAQALAAcKNAoZlQBRAQABNQAECgMIAwAGAAAAAA==.Hecklefish:BAACNQAFFH8GAAIbAAQKpyRSCQCvAQAbAAQKpyRSCQCvAQA1AAQKfykAAxsACQqiJhECAOYDABsACQqiJhECAOYDACAAAgqqGFJkAJUAAAAA.Hellik:BAAANQABCgMIAwAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAABNQAECn8oAAIJAAgKkREmYAD9AQAJAAgKkREmYAD9AQAAAA==.Highdegrees:BAAANQAECgQIBQAAAA==.Hinatta:BAAANQAECgEIAQABNQAECgcIIQALAFUVAA==.Hitagi:BAAANQAECgUIEwAAAA==.',
Ho='Hole:BAAANQAECgEIAgAAAA==.Hollo:BAAANQAECgMICAAAAA==.Holyblasts:BAABNQAECn8lAAISAAgKgiNCKQAfAwASAAgKgiNCKQAfAwAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQABCgMIBAABNQADCgYIBwAGAAAAAA==.Horsey:BAAANQAECgYIBwABNQAECggIFwAWAKIeAA==.Hownow:BAAANQADCgIIAgAAAA==.',
Hu='Huler:BAAANQADCgYIBgAAAA==.Hummingbird:BAAANQAECgQIBwABNQAECgkJGwAUANMeAA==.Hungus:BAAANQAECgQIBgAAAA==.Hurtszick:BAAANQAECgQICQAAAA==.',
Hy='Hydrotiger:BAAANQAECgUIBwABNQAECgkJMAAIAOwhAA==.',
['Hä']='Härasou:BAAANQADCgYIEwAAAA==.',
Il='Illiturtle:BAABNQAECn8cAAMhAAcK5x2iJQAVAgAhAAcK5x2iJQAVAgARAAEKRgtRMgAwAAAAAA==.',
Im='Imnotthtgood:BAAANQADCggIGgAAAA==.',
In='Indever:BAAANQABCgcICAAAAA==.Indigolemon:BAABNQAECn8iAAQCAAgKJBsWLwBkAgACAAgKJBoWLwBkAgATAAMKHhxZNAD6AAAiAAEKxwcbewAkAAABNQAECgkJFgANAIgVAA==.Inkenhancer:BAABNQAECn8iAAIJAAgKjSBsIwD3AgAJAAgKjSBsIwD3AgAAAA==.Inscissor:BAAANQAFFAMIAwAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Iy='Iyari:BAAANQADCgYIDwAAAA==.',
Ja='Jaffaar:BAAANQADCggICAAAAA==.Jamie:BAABNQAECn8cAAMSAAkKZxLCuACmAQASAAcKrRDCuACmAQAjAAQKDBFjPQAFAQAAAA==.',
Je='Jeynsa:BAAANQAECgYICgABNQAECgkJLAACAA8bAA==.',
Ji='Jingadingado:BAAANQADCgYIBgAAAA==.',
Jo='Jollyollie:BAAANQADCgQIBQAAAA==.Joppy:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQAECgQICQAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jë']='Jëf:BAAANQADCgIIAgAAAA==.',
['Jô']='Jôker:BAAANQAECgYIDwAAAA==.',
Ka='Kacho:BAAANQAECgEIAQAAAA==.Kaelara:BAAANQAECggIDgAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kalano:BAAANQADCggIDAAAAA==.Kaorii:BAAANQAECgMIAwAAAA==.Kappo:BAAANQAECgcIEQAAAA==.Karryn:BAAANQADCgQIAwAAAA==.Kathorall:BAABNQAECn8hAAIbAAgK7A9JewAUAgAbAAgK7A9JewAUAgAAAA==.Kawaiihealer:BAABNQAECn8hAAMLAAcKVRXwbQDPAQALAAcKVRXwbQDPAQAcAAIKzgNfbgBJAAAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIBQAAAA==.Keledril:BAAANQAECggIDwAAAA==.Kemper:BAABNQAECn8dAAMkAAcKcA9bCADOAQAkAAcKcA9bCADOAQAbAAMKlQdBLgGGAAAAAA==.Kerrs:BAAANQAECgMICQAAAA==.Kerrst:BAAANQAECgMIBQAAAA==.Kerrz:BAAANQAECgIIAwAAAA==.',
Ki='Kiamonk:BAAANQAECggICAAAAA==.Kiddyl:BAAANQADCgYIFAAAAA==.Kidneypopper:BAAANQAECgUIBQABNQAECgkJKQAEALIhAA==.Kidyll:BAAANQADCgYIBgAAAA==.Kievit:BAAANQAECgYIBwAAAA==.Kir:BAABNQAECn8ZAAMBAAgKzxZuKwBCAgABAAgKzxZuKwBCAgAhAAYKnBI0OQB2AQABNQAECggIHAASAFsWAA==.Kittana:BAABNQAECn8nAAIUAAgKOx0sMQCeAgAUAAgKOx0sMQCeAgAAAA==.Kittyhawke:BAABNQAECn8WAAINAAkKiBUjBgCsAgANAAkKiBUjBgCsAgAAAA==.',
Kk='Kkelhus:BAABNQAECn8XAAIHAAgKLhXfEAAWAgAHAAgKLhXfEAAWAgABNQAFFAIIBQAaAC0QAA==.Kkonetica:BAAANQAECgIIAgABNQAFFAIIBQAaAC0QAA==.Kkrantuq:BAACNQAFFH8FAAMaAAIKLRBWDwCTAAAaAAIKLRBWDwCTAAAeAAEKcwKcIgA7AAA1AAQKfyoAAhoACQrSGvgIAOUCABoACQrSGvgIAOUCAAAA.Kkylar:BAAANQAECgcIEwABNQAFFAIIBQAaAC0QAA==.',
Kl='Klariityy:BAABNQAECn8mAAMLAAkK3hR5QgBeAgALAAkK3hR5QgBeAgAcAAEKAACVfQAsAAAAAA==.Klarity:BAAANQAECggIEgAAAA==.Klarityqt:BAAANQAECgQIBAAAAA==.Klarityx:BAACNQAFFH8MAAIEAAQKJwqFKwAqAQAEAAQKJwqFKwAqAQA1AAQKf0YAAgQACQoII/UXAHQDAAQACQoII/UXAHQDAAAA.',
Kn='Knownentity:BAAANQAECgUIEAAAAA==.',
Ko='Koma:BAAANQADCggJCAABNQAFFAcIHgAJANklAA==.Komatos:BAACNQAFFH8eAAIJAAcK2SWUAAAHAwAJAAcK2SWUAAAHAwA1AAQKfy0AAgkACQrCJr8CANwDAAkACQrCJr8CANwDAAAA.Koreantacos:BAAANQADCgcIDQAAAA==.Koronus:BAAANQADCgcIFwAAAA==.',
Kr='Kracklin:BAAANQAECgYICgAAAA==.',
Ku='Kurisutina:BAAANQAECgQICAAAAA==.',
['Kâ']='Kânamë:BAAANQADCggIDAABNQAECgcIJgAXAD0QAA==.',
['Kê']='Kênsêi:BAABNQAECn8mAAMXAAcKPRBGYgCDAQAXAAcKPRBGYgCDAQADAAMKgwszlgCvAAAAAA==.',
['Kô']='Kôan:BAAANQAECgYIDwAAAA==.',
['Kû']='Kûkâkü:BAAANQAECgQIBAABNQAECgcIJgAXAD0QAA==.',
La='Largetimmy:BAAANQADCggICQABNQAECgkJFgALAC0cAA==.',
Le='Leafyjoe:BAABNQAECn8nAAICAAgKuBuNJgCcAgACAAgKuBuNJgCcAgAAAA==.Lechencaja:BAAANQADCgYJBgABNQAECgcIEgAGAAAAAA==.Led:BAAANQAECgEIAQAAAA==.Legendarybob:BAAANQADCgYIBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAABNQAECn8jAAQXAAgKTQjMewApAQAXAAcKFAbMewApAQAWAAYK3wgKYgATAQADAAcKBwZVfgD9AAAAAA==.Legö:BAAANQAECggIBgABNQAECggIIwAXAE0IAA==.Leitbur:BAAANQAECggICQAAAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECgkJKAAeAI8dAA==.',
Li='Libidine:BAAANQADCgIIAgABNQAECgYIEgAGAAAAAA==.Lido:BAABNQAECn8bAAMCAAkKWwU/eADlAAACAAgKWwU/eADlAAAiAAgK0gbpSwDaAAAAAA==.Lilcowdk:BAAANQAECgIIAgABNQAECgkJKgANAGIZAA==.Lildeemon:BAABNQAECn8qAAMNAAkKYhnMCABuAgANAAgKrhbMCABuAgAMAAgKshdeYgAuAgAAAA==.Lilspyro:BAAANQAECgQIBAAAAA==.Lionsinpride:BAAANQADCgYIBgAAAA==.Livathian:BAABNQAECn8fAAISAAgKsAyXvgCZAQASAAgKsAyXvgCZAQAAAA==.Lizwiz:BAAANQAECgYICgAAAA==.',
Lo='Lokrah:BAAANQABCgMIBgAAAA==.Lothuial:BAAANQADCgcIBwAAAA==.',
Lu='Lucerubis:BAABNQAECn8XAAIaAAkKEwr6GgD8AQAaAAkKEwr6GgD8AQAAAA==.Lucifiux:BAAANQAECgcIEwAAAA==.Lunavel:BAABNQAECn8fAAMSAAcKmhKSzQB6AQASAAYKYBWSzQB6AQAjAAUK9A3vRQDUAAAAAA==.',
Ly='Lydo:BAAANQAECggICwAAAA==.',
Ma='Macaria:BAAANQAECgQIBAAAAA==.Maggette:BAAANQADCgYIBgABNQAECggIJAAMAAwaAA==.Magicdan:BAAANQADCgYICAAAAA==.Malnorr:BAABNQAECn8gAAMMAAkKhBSSYwArAgAMAAgKtBOSYwArAgANAAIKRhYfUgCHAAAAAA==.Manatarm:BAAANQADCgIIAgAAAA==.Mandragon:BAAANQADCgUIBQABNQAECgkJHAAUAPUeAA==.Mangol:BAABNQAECn8ZAAMSAAkKBiS+DACbAwASAAkKBiS+DACbAwAUAAMKGxTi1QDNAAAAAA==.Manudei:BAABNQAECn8VAAIUAAgKuyBJHgD2AgAUAAgKuyBJHgD2AgAAAA==.Marryg:BAAANQAECgIIAgABNQAECgkJFwAfAD4YAA==.Maryillo:BAACNQAFFH8XAAICAAcKJRxABABpAgACAAcKJRxABABpAgA1AAQKfycAAgIACQquJaINAFwDAAIACQquJaINAFwDAAAA.Mattdaemon:BAAANQAECgcIEwAAAA==.',
Mc='Mcmannis:BAAANQAECggIDwAAAA==.Mcpoltrain:BAAANQAECgcIDwAAAA==.',
Me='Mennil:BAAANQAECgYIEgAAAA==.Mental:BAAANQAECgQIBgABNQAFFAYIEQAhAAwPAA==.Meolater:BAABNQAECn8mAAIZAAkKLBkvDwC0AgAZAAkKLBkvDwC0AgAAAA==.Mesmerise:BAAANQAECgcIDgAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECgkJKAAeAI8dAA==.Mindgoblinn:BAABNQAECn8fAAILAAcKaxY/agDbAQALAAcKaxY/agDbAQAAAA==.Minicookie:BAAANQAECgQIBAAAAA==.Minyaw:BAAANQAECgUIDAABNQAECggIMgAaAH8cAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQAECgUIDAAAAA==.',
Mm='Mmchocolat:BAAANQAECgUIAwAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEBNQAECn8vAAIkAAkKtyCOAQBOAwAkAAkKtyCOAQBOAwAAAA==.Moolissa:BAABNQAECn8bAAIJAAgKmArRfwChAQAJAAgKmArRfwChAQAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgMIBgAAAA==.Morbidchaos:BAACNQAFFH8fAAIhAAcKJCZRAADpAgAhAAcKJCZRAADpAgA1AAQKfykAAyEACQrfIigJAEMDACEACQrfIigJAEMDAAEAAgq7H2BvALUAAAAA.Morkels:BAAANQAECgcIDAABNQAFFAkJIwAlABUkAA==.',
Mu='Muddyshark:BAABNQAECn8YAAMWAAgK4AcoXgAlAQAWAAcKswcoXgAlAQAXAAYKIAVgjQDsAAAAAA==.Mukatsuku:BAAANQAECgUIDgAAAA==.Muscida:BAAANQAECgQIBQAAAA==.',
My='Mykhawk:BAAANQADCgUICAAAAA==.',
['Mâ']='Mâyüri:BAAANQAECgMIAwABNQAECgcIJgAXAD0QAA==.',
Na='Naeth:BAABNQAECn8pAAISAAgKDiGySwCuAgASAAgKDiGySwCuAgAAAA==.Nalrot:BAAANQAECgEIAQABNQAECgcIDgAGAAAAAA==.Narcine:BAABNQAECn8gAAIbAAkKnR5jIgAMAwAbAAkKnR5jIgAMAwAAAA==.',
Ne='Neciecakes:BAABNQAECn8vAAMUAAkKGRkkLAC0AgAUAAkKGRkkLAC0AgASAAEK4BB7mQE3AAAAAA==.Nee:BAABNQAECn8kAAMYAAkK1BMyTQAsAgAYAAkK1BMyTQAsAgAJAAYKuBAIjwB7AQAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nekus:BAAANQADCgcIBwAAAA==.Nelor:BAABNQAECn8bAAIhAAcKCBNFLwDDAQAhAAcKCBNFLwDDAQAAAA==.Nerftitty:BAAANQADCgUIBQAAAA==.Nettles:BAAANQAECgQICgAAAA==.Neverheal:BAAANQADCgEIAQAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ng='Ngàymai:BAAANQADCgQIBAAAAA==.',
Ni='Nicelikerice:BAAANQADCgcIBwAAAA==.Nightwatchr:BAAANQAECggIDQAAAA==.Nisona:BAAANQAECgQIBwAAAA==.Nitashal:BAABNQAECn8iAAMZAAkKch2ODQDMAgAZAAkKch2ODQDMAgAKAAEKAACTOwA2AAABNQAFFAQIBwAJAMQNAA==.',
No='Nokthro:BAAANQADCgYJBgABNQAFFAQICAAKADoTAA==.Noremac:BAAANQADCggIEAAAAA==.',
Nu='Nubsaiboot:BAAANQAECgUICAABNQAECggIHAASAFsWAA==.',
Ny='Nythariel:BAAANQADCggIHAAAAA==.',
['Në']='Nëzükõ:BAAANQADCgYIBgABNQAECgcIJgAXAD0QAA==.',
Od='Odi:BAAANQAECgUIDAAAAA==.',
Ok='Okiaat:BAAANQAECgYIBwAAAA==.',
Ol='Oliviawildè:BAABNQAECn8lAAMUAAkKPRq2HQD5AgAUAAkKPRq2HQD5AgASAAEKAAA3xwEhAAAAAA==.',
On='Onezero:BAAANQAECgIIAgAAAA==.Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAAANQAECgYIEgAAAA==.Pallyforhire:BAAANQAECgQIBQAAAA==.Panfriedrice:BAAANQAECggIDAAAAA==.Pantyblossom:BAABNQAECn8aAAILAAgKrx0SMQChAgALAAgKrx0SMQChAgABNQAECggIJAAMAAwaAA==.',
Pe='Peaches:BAAANQAECgQIBgAAAA==.Peewees:BAAANQADCgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAABNQAECn8rAAINAAcKFB85BgCpAgANAAcKFB85BgCpAgAAAA==.Peladin:BAAANQABCgcJDAAAAA==.Pelado:BAAANQABCgIIAgAAAA==.Pelito:BAAANQADCgUJBQAAAA==.Pell:BAAANQADCgEIAQAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQAECgIIAgABNQAECggIKQAQALEPAA==.',
Ph='Phaeddrus:BAAANQAECgQIBQAAAA==.Phobos:BAABNQAECn8cAAIlAAgKiglnDQB1AQAlAAgKiglnDQB1AQAAAA==.Phogood:BAAANQAECgMIAwAAAA==.Phrix:BAAANQAECgQIBAABNQAFFAQICAAKADoTAA==.',
Pi='Pinecone:BAABNQAECn8bAAICAAkKsyMQGgD2AgACAAkKsyMQGgD2AgAAAA==.',
Pl='Ploppster:BAAANQADCggIDQAAAA==.Plot:BAAANQAECggIEwAAAA==.Plsno:BAAANQADCgcICQAAAA==.',
Po='Poekimaw:BAAANQAECgIIAgAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAACNQAFFH8LAAISAAQKQSTmCwCGAQASAAQKQSTmCwCGAQA1AAQKfyUAAhIACQqVJd8RAH8DABIACQqVJd8RAH8DAAAA.Poppinin:BAABNQAECn8fAAISAAgKPhCanADkAQASAAgKPhCanADkAQAAAA==.Potshotbot:BAAANQADCgYIBgAAAA==.Powerwordhug:BAAANQAECgYIEQABNQAECggIGAABAMERAA==.',
Pr='Praedo:BAAANQADCgYIBgAAAA==.Prevaleon:BAAANQAECgEIAQAAAA==.',
Ps='Psychaos:BAAANQAECggIEQAAAA==.Psychostorm:BAAANQAECgcICgAAAA==.Psychritic:BAAANQAECgcJEwAAAA==.Psyence:BAAANQADCgcIDgAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purpletotem:BAAANQAECgcIDgAAAA==.Purrsnikitty:BAAANQAECgMIAwAAAA==.Pus:BAAANQADCgYIBgABNQAECggILAAQAAogAA==.',
Qo='Qookd:BAAANQAECgQICgAAAA==.',
Qu='Quillmane:BAAANQAECgYICwABNQAFFAQICAAKADoTAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAABNQAECn8iAAIhAAkKCh10FQC2AgAhAAkKCh10FQC2AgAAAA==.Ragingdeath:BAAANQADCgYIBwAAAA==.Rainakamugi:BAAANQAECgQJBwABNQAFFAUICwALAH4JAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQAECgUIDQAAAA==.Ralphanir:BAABNQAECn8gAAMYAAcK7xJNgQCEAQAYAAcK7xJNgQCEAQAJAAMKnQ+c7QC0AAAAAA==.Raskreia:BAAANQADCggICQAAAA==.Raygyu:BAAANQADCgQIBAABNQAECgkJHQAbAEggAA==.Rayvoker:BAAANQADCgYJDAABNQAECgkJHQAbAEggAA==.',
Re='Reek:BAABNQAECn8bAAIeAAgKIxLNMQASAgAeAAgKIxLNMQASAgAAAA==.Reignz:BAAANQAECgcIBwAAAA==.Rexari:BAAANQAECgUIEwAAAA==.Rezmae:BAAANQAECgIIBAAAAA==.',
Rh='Rhaiordan:BAAANQAECgIIAgAAAA==.',
Ri='Riniedaze:BAAANQADCggIEgAAAA==.',
Ro='Rockandstone:BAACNQAFFH8NAAIUAAUKjwxTDwBqAQAUAAUKjwxTDwBqAQA1AAQKfzEAAhQACQoKF683AIMCABQACQoKF683AIMCAAAA.Rocki:BAAANQAECgEJAQABNQAFFAMIBwANAAMWAA==.Rondrous:BAAANQADCggICAABNQAECgcIDgAGAAAAAA==.Rooty:BAAANQAECgQICgABNQAECgkJGAAWAOYZAA==.Roron:BAAANQAECgQIBAAAAA==.',
['Rì']='Rìmûrü:BAAANQADCggICAABNQAECgcIJgAXAD0QAA==.',
Sa='Safetyspork:BAAANQAECgYIDQAAAA==.Sagë:BAAANQAECgUIDgAAAA==.Sakonutz:BAABNQAECn8mAAIiAAgKFwz/MACOAQAiAAgKFwz/MACOAQAAAA==.Salsa:BAAANQADCgcIDwAAAA==.Saresh:BAABNQAFFH8KAAILAAQKYBSjFgA8AQALAAQKYBSjFgA8AQAAAA==.Sathariel:BAAANQABCgIJAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.Savages:BAAANQADCggICAABNQAECggIHAAYAD0VAA==.',
Sc='Schlee:BAAANQABCgYJCAAAAA==.Screeps:BAAANQABCgcIDgABNQADCgYIBwAGAAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAABNQAECn8kAAIMAAgKDBoRSQB0AgAMAAgKDBoRSQB0AgAAAA==.Selceor:BAAANQADCggIDgAAAA==.Sendh:BAABNQAECn8VAAIhAAcK2ROFMQCwAQAhAAcK2ROFMQCwAQAAAA==.Sermet:BAAANQAECgYIEAABNQAECggIIQAhAAghAA==.Sermonn:BAAANQAECgQIBgAAAA==.Serous:BAAANQAECgUIEwAAAA==.Serwellmet:BAAANQAECgMIAwABNQAECggIIQAhAAghAA==.Seshin:BAAANQAECggIIgAAAQ==.Set:BAAANQADCggICAABNQAFFAQICAAKADoTAA==.Setal:BAACNQAFFH8IAAIKAAQKOhPSBgArAQAKAAQKOhPSBgArAQA1AAQKfzAAAwoACQrnIT0FAD4DAAoACQrnIT0FAD4DACUAAQqjCeYiADkAAAAA.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECggIMgAaAH8cAA==.Shammoo:BAAANQAECgMIAgAAAA==.Shawz:BAAANQADCgYIBgAAAA==.Shcho:BAAANQAECgIIAwAAAA==.Sheepe:BAABNQAECn8aAAMPAAcKcRVyDgDGAQAPAAcKcRVyDgDGAQAQAAEK+QPMWwEmAAAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgQIBAAAAA==.Shinyscalp:BAABNQAECn8gAAIQAAkKtiMhDQCPAwAQAAkKtiMhDQCPAwAAAA==.Shkanna:BAAANQAECggIDQAAAA==.Shogunz:BAAANQAECgUJBgAAAA==.',
Si='Simaria:BAAANQAECgEIAQAAAA==.Sinapaladin:BAABNQAECn8cAAMSAAgKWxYwdwA6AgASAAgKWxYwdwA6AgAjAAYKTBGtNwApAQAAAA==.Siomara:BAABNQAECn8hAAMcAAgK/hHwIwAPAgAcAAgK/hHwIwAPAgALAAYKcg8tlQBRAQAAAA==.Sivanya:BAAANQADCgYJBgAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgYIBwAAAA==.Skrepz:BAAANQABCgIJAgABNQADCgYIBwAGAAAAAA==.Skypri:BAAANQAECgQIBgAAAA==.',
Sl='Slabbcrakle:BAAANQADCgUIBQAAAA==.Slabbhammer:BAAANQADCgYIBgAAAA==.Slabbster:BAAANQAECgcIEQAAAA==.',
Sm='Smooshednewt:BAABNQAECn8wAAIIAAkK7CE8BQA4AwAIAAkK7CE8BQA4AwAAAA==.',
Sn='Sne:BAAANQAECgQIEQAAAA==.Snoop:BAABNQAECn8bAAIEAAgKKQ9ZvgAGAgAEAAgKKQ9ZvgAGAgAAAA==.',
So='Soloa:BAAANQAECgQICAAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAABNQAECn8sAAICAAkKDxuHGAABAwACAAkKDxuHGAABAwAAAA==.Sosneaky:BAAANQADCgMICAAAAA==.Soulfuria:BAAANQAECggIBwAAAA==.',
Sp='Spekk:BAAANQADCgYICgAAAA==.Speknawz:BAACNQAFFH8FAAMaAAQK7AXSDADXAAAaAAMKvALSDADXAAAeAAEKSwzuHwBHAAA1AAQKfx4AAxoACQo0Fq0RAGUCABoACQqJFK0RAGUCAB4AAwojGnVzANsAAAAA.Splatzill:BAAANQADCgIIAgABNQAFFAMIBQAQANoGAA==.Spoiledangel:BAABNQAECn8cAAMLAAYKbhgLfgCaAQALAAYKbhgLfgCaAQAcAAIKzgSGbwBGAAAAAA==.Spoonhat:BAAANQADCggIDgABNQAECgYIDQAGAAAAAA==.Springz:BAAANQAFFAEIAQAAAA==.',
St='Staggering:BAABNQAECn8iAAIJAAkKExbQQwBjAgAJAAkKExbQQwBjAgAAAA==.Starryniight:BAAANQAECgUIEQAAAA==.Stephsux:BAABNQAECn8WAAINAAgKYRK8CwA7AgANAAgKYRK8CwA7AgAAAA==.Stickers:BAAANQAECgMJBAAAAA==.Stormbringer:BAAANQAECgQIBAAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgYIBwAAAA==.Suika:BAAANQAECgQIBAAAAA==.Sunaellia:BAAANQADCgEIAQAAAA==.Supanova:BAABNQAECn8tAAMcAAkK9hdbGACOAgAcAAgKIhpbGACOAgALAAcKEx3XPABzAgABNQAECgkJMAAIAOwhAA==.Surwick:BAABNQAECn8cAAISAAgKBQwerwC7AQASAAgKBQwerwC7AQAAAA==.',
Sv='Svelus:BAACNQAFFH8WAAISAAcKHCWzAADfAgASAAcKHCWzAADfAgA1AAQKfyoAAhIACQofJvgMAJoDABIACQofJvgMAJoDAAAA.',
Sw='Swingin:BAABNQAECn8bAAIjAAcKehDQLwBcAQAjAAcKehDQLwBcAQAAAA==.',
Sy='Sycophancy:BAAANQAECgEIAwABNQAECgkJMAAIAOwhAA==.Synaptichole:BAAANQAECgQICAAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tachealz:BAABNQAECn8cAAMYAAgKPRWuXAD2AQAYAAgKPRWuXAD2AQAIAAQKxgQlKgC9AAAAAA==.Talos:BAAANQAECgEIAQAAAA==.Tanurhide:BAAANQADCgQIBAAAAA==.Taropie:BAAANQAECgQIBAAAAA==.Tartan:BAABNQAFFH8JAAIgAAQKAxu+EQAcAQAgAAQKAxu+EQAcAQAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.Taylorswif:BAAANQADCgEIAQABNQAECgkJIgAFAJQgAA==.',
Te='Tearal:BAAANQAECgEIAQAAAA==.Techi:BAAANQADCgIIAgAAAA==.Teewat:BAAANQAECgQIBAAAAA==.Temres:BAABNQAECn8hAAQhAAgKCCHrEgDRAgAhAAgKCCHrEgDRAgABAAUKOBxQRwCIAQARAAEKFx3hKwBRAAAAAA==.Tendermulva:BAABNQAECn8aAAIOAAkKeQiACwCxAQAOAAkKeQiACwCxAQAAAA==.Terekk:BAAANQADCggIHwAAAA==.Teshtara:BAAANQAECgQICQABNQAECgkJLAACAA8bAA==.',
Th='Theod:BAAANQADCgYIBwAAAA==.Thesauce:BAACNQAFFH8UAAMfAAUK6yTkBQCxAQAfAAQK6yTkBQCxAQAmAAQKxxmCBABLAQA1AAQKfyMAAx8ACQpRJfAGAGADAB8ACQrrJPAGAGADACYABwrlJGIIAKMCAAAA.Theusaus:BAAANQAECggICQAAAA==.Thiaw:BAAANQAECgQICQAAAA==.Thickette:BAAANQADCgQIBAABNQAECggIJAAMAAwaAA==.Thimo:BAAANQADCgEIAQABNQADCggICQAGAAAAAA==.Thrikal:BAABNQAECn8vAAIBAAkK1RJpMAAgAgABAAkK1RJpMAAgAgAAAA==.Thugd:BAAANQAECgMIAwABNQAECggIGwAEACkPAA==.',
To='Tomsmg:BAACNQAFFH8FAAIEAAMKwgzJOgDTAAAEAAMKwgzJOgDTAAA1AAQKfyUAAwQACQovGxZ8AIYCAAQACQovGxZ8AIYCAAUAAQp0B4xNACoAAAAA.Toofs:BAABNQAECn8ZAAMQAAcKCCIGTACiAgAQAAcK4yAGTACiAgAPAAIKwySpHgDHAAAAAA==.Totemsh:BAAANQAECgIIAgABNQAECgkJGwAUANMeAA==.Toxifay:BAABNQAECn8WAAIaAAcKIQZ3LABZAQAaAAcKIQZ3LABZAQAAAA==.',
Tr='Traell:BAAANQADCgYIDAAAAA==.Trd:BAAANQABCggICgAAAA==.Treehuggles:BAAANQAECgUIBwABNQAECggIGAABAMERAA==.Trollbanæ:BAAANQADCgUIBQAAAA==.Trousersnake:BAAANQADCggICAABNQAECggIHgAVAIojAA==.Truedat:BAAANQADCgQIBwAAAA==.',
['Tì']='Tìõ:BAAANQADCgYIBgABNQAECgcIJgAXAD0QAA==.',
Ug='Ughtismo:BAAANQADCgUJBQAAAA==.',
Un='Undeadban:BAAANQABCgcJCQAAAA==.',
Us='Usagiknight:BAAANQAECgcIDwAAAA==.Ushii:BAAANQAECgQIEQAAAA==.',
Va='Valdemort:BAAANQADCgQIBAABNQAECgYIDQAGAAAAAA==.Valei:BAAANQAECgMIAwAAAA==.',
Ve='Veganforlife:BAAANQADCgIIAwAAAA==.',
Vi='Vinda:BAABNQAECn8vAAIcAAkKExmlGgBzAgAcAAkKExmlGgBzAgAAAA==.Vivixia:BAAANQAECgYIDwAAAA==.',
Vo='Volgrath:BAAANQAECggIEAAAAA==.Voodoolock:BAAANQAECgQIDgABNQAECggIHAAYAD0VAA==.',
Vu='Vuletronix:BAAANQADCgIIAgAAAA==.',
Wa='Walkingboot:BAAANQADCgQIBAAAAA==.Wallo:BAABNQAECn8pAAIQAAgKsQ/VmgDVAQAQAAgKsQ/VmgDVAQAAAA==.Washedbolt:BAAANQAECgIIBAAAAA==.Washedpyro:BAAANQAECgIIBQAAAA==.Washedzebu:BAABNQAECn8gAAMeAAcKPxlANQD/AQAeAAcKPxlANQD/AQAaAAUKzA+YNQAHAQAAAA==.Watsatotem:BAAANQAECgcICgAAAA==.Wayfairkid:BAAANQAECgEIAQAAAA==.',
We='Weeb:BAACNQAFFH8jAAIlAAkKFSQlAAC7AwAlAAkKFSQlAAC7AwA1AAQKfyEAAyUACQqTJiQBAJgDACUACQqTJiQBAJgDAAoACArSF6QVAO8BAAAA.Werken:BAAANQAECgIIAgAAAA==.',
Wh='Whatsthis:BAAANQAECgUIBQAAAA==.Whiterabbitt:BAAANQADCggILwAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQAECgEIAQAAAA==.Wilmabfiymr:BAAANQAECgEIAQAAAA==.',
Wo='Woa:BAAANQAECgcIBgAAAA==.Woofwoofwoof:BAAANQAECgQICQAAAA==.',
Wr='Writhe:BAAANQAFFAEIAQABNQAFFAcIGAAmAAUjAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Xq='Xquori:BAAANQADCggICwAAAA==.',
Ye='Yeeloow:BAAANQADCgYIDQAAAA==.',
Ys='Yshaarj:BAAANQADCggIEgAAAA==.',
Yu='Yulok:BAACNQAFFH8YAAMmAAcKBSNQAACyAgAmAAcK3yJQAACyAgAfAAcKmBV5AwAnAgA1AAQKfyUAAyYACQqgJt0AANADACYACQqgJt0AANADAB8AAwp3I1I8AC4BAAAA.Yuukí:BAAANQADCggICAABNQAECgkJKQASALggAA==.',
['Yâ']='Yâmamôto:BAAANQADCgQIBAABNQAECgcIJgAXAD0QAA==.',
['Yú']='Yúúki:BAABNQAECn8cAAIDAAgKKR27IACrAgADAAgKKR27IACrAgABNQAECgkJKQASALggAA==.',
Za='Zaberra:BAABNQAECn8oAAIOAAkKdxfFAwCxAgAOAAkKdxfFAwCxAgABNQAECgkJLAACAA8bAA==.Zanarkand:BAAANQAECgUIEQAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zerofort:BAAANQAECgYIBgAAAA==.Zexexe:BAAANQAECgcIDQABNQAFFAcIGQACABIgAA==.',
Zi='Zibroth:BAABNQAECn8kAAMiAAkKARTYHABIAgAiAAkKARTYHABIAgACAAIKcAZjnQBhAAAAAA==.Zieg:BAAANQAECgcICwABNQAFFAMIAwAGAAAAAA==.Zina:BAAANQAECgIIAgAAAA==.',
['Áo']='Áodh:BAAANQAECgQIBAAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQAECgQIEAAAAA==.',
['Ýu']='Ýuuki:BAABNQAECn8pAAISAAkKuCA9KAAjAwASAAkKuCA9KAAjAwAAAA==.',
['ßr']='ßrß:BAAANQAECggIEgABNQAECggILAAQAAogAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
