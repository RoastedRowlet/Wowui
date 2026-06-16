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

local lookup = {'Paladin-Retribution','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Druid-Restoration','Paladin-Holy','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warlock-Demonology','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Monk-Mistweaver','Druid-Feral','DeathKnight-Blood','Evoker-Augmentation','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Rogue-Outlaw','Druid-Guardian',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAYJFQABAN0aAA==.Alodiar:BAAALgAECgMJAwAAAA==.',
Am='Amrin:BAAALgAECgkJBgAAAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8jAAIBAAgJEB84LgBGAgABAAgJEB84LgBGAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8PAAICAAQJpQl8LQDLAAACAAQJpQl8LQDLAAAuAAQKf0UAAgIACQm7HMgJALYCAAIACQm7HMgJALYCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgADCgEJAQABLgAECgMJAwADAAAAAA==.Ariis:BAAALgAECgQJBAAAAA==.Arkanis:BAABLgAECn80AAIEAAkJ3Rx/GACCAgAEAAkJ3Rx/GACCAgAAAA==.Arïel:BAABLgAECn8pAAQFAAgJYxuGDwB1AgAFAAgJXhuGDwB1AgAGAAEJfRthZgBFAAAHAAEJMAVTkwAkAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAECgkJFwAIAM4hAA==.Banidor:BAAALgAECgIJAgABLgAECgMJAwADAAAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECgIJAgAAAA==.',
Bi='Bishop:BAABLgAECn8hAAMBAAgJjBKmYQCrAQABAAgJjBKmYQCrAQAJAAMJRglAbQB9AAAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMKAAYJFAjERQCtAAALAAYJAwZqZADHAAAKAAYJnwbERQCtAAAAAA==.',
Br='Broadfang:BAACLgAFFH8lAAMMAAgJQB8FAwBtAQAMAAUJ9yIFAwBtAQANAAcJrBNZDwA4AQAuAAQKfyQABAwACQlPJZ0cAFoCAA0ABwliIpAYAGcCAAwABgnHJJ0cAFoCAA4ABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwABLgAFFAcJAwADAAAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJEAAAAA==.Bullorly:BAACLgAFFH8iAAIPAAYJISHxJgDCAQAPAAYJISHxJgDCAQAuAAQKfyEAAg8ACQnqJAkKAB4DAA8ACQnqJAkKAB4DAAAA.Bullwînkle:BAAALgADCgcJBwABLgAECgkJGQAQAD8FAA==.Bungulators:BAEALgAFFAEJAQABLgAFFAIJBgARAEUJAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgAECgEJAQAAAA==.',
Cl='Clickshot:BAACLgAFFH8RAAIMAAQJHiSsFwCgAQAMAAQJHiSsFwCgAQAuAAQKf0wAAwwACQk/JioCAG0DAAwACQk/JioCAG0DAA0ABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgcJCwAAAA==.Clipee:BAAALgAECgkJEgAAAA==.Clipeskeg:BAABLgAECn8jAAMSAAkJQhyTDgBOAgASAAkJQhyTDgBOAgATAAEJFwvXkgA6AAAAAA==.Clipex:BAAALgAECgkJEAAAAA==.',
Co='Connor:BAAALgAFFAEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAABLgAFFH8FAAIUAAMJoBFdewDnAAAUAAMJoBFdewDnAAAAAA==.Cryptus:BAAALgADCgMJAQABLgAECggJHgAVABcgAA==.',
Cy='Cynicboom:BAAALgADCgQJBAAAAA==.Cynîc:BAAALgAECgcJCQAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8oAAMHAAkJlxgEFwAuAgAHAAkJlxgEFwAuAgAFAAEJpA3AewAtAAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn82AAQIAAkJjw/eOgCnAQAIAAkJjw/eOgCnAQACAAYJNAg3TQDSAAAWAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAFFAQJBQAOAHsZAA==.',
De='Deathbooze:BAACLgAFFH8WAAIPAAUJ/CAEOACFAQAPAAUJ/CAEOACFAQAuAAQKfywAAg8ACQl2ISEWAMACAA8ACQl2ISEWAMACAAAA.Deathmikee:BAACLgAFFH8MAAMXAAQJpxdpGAAfAQAXAAQJkRdpGAAfAQAPAAMJnBB9nADXAAAuAAQKf0IAAg8ACQkEIkkKABsDAA8ACQkEIkkKABsDAAAA.Demonea:BAAALgAECgEJAQAAAA==.Demonrush:BAAALgAECgEJAQABLgAFFAEJAwADAAAAAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQADAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgkJDwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIHAAcJGyFPEwBaAgAHAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAABLgAECn8ZAAIOAAgJYAUiKwBJAQAOAAgJYAUiKwBJAQAAAA==.Drakos:BAAALgAECgkJEAAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8MAAILAAQJOxoBFgBZAQALAAQJOxoBFgBZAQAuAAQKfykAAgsACQnQHzkYAIoCAAsACQnQHzkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAIMAAMJ+xV6YQDaAAAMAAMJ+xV6YQDaAAABLgAFFAUJCAAYAGYbAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAACLgAFFH8OAAILAAQJoiGeDwCDAQALAAQJoiGeDwCDAQAuAAQKfzYAAwsACQlyIYwMAKACAAsACQlyIYwMAKACAAoAAwmAG6FFAK4AAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8PAAIVAAQJgRDRMADiAAAVAAQJgRDRMADiAAAuAAQKfzAAAxUACQlMHT8TAH0CABUACQlMHT8TAH0CABMAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn9NAAMEAAkJVCahAADZAwAEAAkJVCahAADZAwAZAAEJ/wZxogAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIaAAcJRxDmLQAPAQAaAAcJRxDmLQAPAQAAAA==.Employee:BAACLgAFFH8eAAILAAcJtx0TAwDGAQALAAcJtx0TAwDGAQAuAAQKfyIAAwsACQmvJVYBALsDAAsACQmvJVYBALsDABEAAwmCGvoxALUAAAAA.',
Es='Estias:BAAALgAECgcJCAAAAA==.',
Ev='Evangeliné:BAABLgAECn8UAAIBAAYJ0gTI/QC3AAABAAYJ0gTI/QC3AAABLgAECgkJRQAGAHkZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.Execfive:BAAALgAECgEJAQAAAA==.',
Fe='Femboi:BAABLgAECn8UAAIbAAgJFxFEUQCOAQAbAAgJFxFEUQCOAQAAAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8IAAIOAAMJBh9mGQABAQAOAAMJBh9mGQABAQAuAAQKfyoAAg4ACQlfHIUJAIUCAA4ACQlfHIUJAIUCAAAA.',
Fr='Freshlight:BAAALgAECgYJBgABLgAFFAQJCwAVAFwaAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galak:BAAALgADCgUJBQABLgAFFAYJFQABAN0aAA==.Galatea:BAACLgAFFH8VAAIBAAYJ3RrjGwCRAQABAAYJ3RrjGwCRAQAuAAQKfyoAAgEACQmbIlANAPkCAAEACQmbIlANAPkCAAAA.Galifen:BAACLgAFFH8PAAICAAQJZSUCDgCzAQACAAQJZSUCDgCzAQAuAAQKf1AAAgIACQl9JmYAAJEDAAIACQl9JmYAAJEDAAAA.Gank:BAABLgAFFH8JAAMcAAQJiBhMBgANAQAcAAMJcx9MBgANAQAdAAEJyANaPABDAAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8yAAMeAAkJshk7CgA7AgAeAAkJshk7CgA7AgAYAAgJZQxBNQBaAQAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8UAAITAAkJFRvwDQBlAgATAAkJFRvwDQBlAgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8tAAMfAAgJxA0mGwA7AQAfAAgJxA0mGwA7AQABAAEJaQN3WAEmAAABLgAFFAQJBwAPACwCAA==.',
Gn='Gnomegrown:BAABLgAECn8yAAICAAgJYxhBGgD2AQACAAgJYxhBGgD2AQAAAA==.',
Go='Goy:BAAALgAFFAIJAwAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDwAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAABLgAECn8YAAMeAAkJaw3JFgBfAQAeAAcJDg7JFgBfAQAYAAYJjASpZwCfAAAAAA==.Hamalainen:BAAALgAECgUJAwABLgAFFAQJCwAVAFwaAA==.Hankthesnake:BAAALgADCgcJGwABLgAECgMJAwADAAAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBQAAAA==.',
Hi='Highcurious:BAAALgAECgYJBwABLgAFFAQJCwAVAFwaAA==.',
Ho='Hobbz:BAACLgAFFH8mAAIBAAcJlxnYDAADAgABAAcJlxnYDAADAgAuAAQKfy8AAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.Holyfans:BAAALgAECgMJAwAAAA==.',
['Hó']='Hólythunder:BAAALgAECgIJAgAAAA==.',
Il='Illandros:BAABLgAECn8oAAIHAAgJ4RK9JACiAQAHAAgJ4RK9JACiAQAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8oAAIWAAkJzxPvCwD1AQAWAAkJzxPvCwD1AQAAAA==.Inspire:BAACLgAFFH8KAAMIAAYJLBskEADxAQAIAAYJLBskEADxAQACAAMJHQbuNQCgAAAuAAQKfxUAAggACAn3HDAjAC8CAAgACAn3HDAjAC8CAAAA.',
Is='Isinia:BAABLgAECn8ZAAIQAAkJPwXYhAAvAQAQAAkJPwXYhAAvAQAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAABLgAECn8eAAIVAAgJFyA4CwDgAgAVAAgJFyA4CwDgAgAAAA==.Jayim:BAABLgAFFH8GAAIIAAMJvAHDVABtAAAIAAMJvAHDVABtAAAAAA==.Jaína:BAABLgAECn8aAAIUAAgJ/gtwgQBxAQAUAAgJ/gtwgQBxAQABLgAECggJJwABAAccAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAFFAQJCwAVAFwaAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAACLgAFFH8LAAIVAAQJXBqyJAA6AQAVAAQJXBqyJAA6AQAuAAQKfzkAAxUACQmSIfgGAC4DABUACQmSIfgGAC4DABMAAwkTEIFuAHAAAAAA.',
Jo='Johnson:BAABLgAECn8oAAIRAAkJyhvCBwCAAgARAAkJyhvCBwCAAgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn80AAIBAAkJYRZdMAA8AgABAAkJYRZdMAA8AgAAAA==.Jormungandr:BAAALgAECgIJAgABLgAFFAQJCwAVAFwaAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAIPAAgJCw1/kQBAAQAPAAgJCw1/kQBAAQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Killnoobs:BAAALgADCgEJAQAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgMJAwADAAAAAA==.Kro:BAABLgAECn8kAAIBAAgJ/BOGXwCvAQABAAgJ/BOGXwCvAQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.Krèios:BAAALgAECgcJCAABLgAFFAUJEgAbAB8OAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.Lenayuh:BAAALgAECgUJCAAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8sAAIPAAkJxRgtJwBkAgAPAAkJxRgtJwBkAgAAAA==.',
Ll='Lloydlei:BAABLgAECn8yAAQQAAkJBh2bHQBxAgAQAAkJdxybHQBxAgAgAAQJ5hWRFQAaAQAhAAMJEhfDJQCBAAAAAA==.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAUJEAAdANQHAA==.',
Lu='Luminå:BAABLgAECn8gAAIhAAkJZhjZCwB9AQAhAAkJZhjZCwB9AQAAAA==.',
Ly='Lylenn:BAAALgAECgYJBgAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn9QAAMaAAkJLSbxAAB2AwAaAAkJLSbxAAB2AwAbAAkJDiWHAwBNAwAAAA==.Malificent:BAABLgAECn8dAAIQAAcJ7R08PQDmAQAQAAcJ7R08PQDmAQAAAA==.Malighn:BAACLgAFFH8HAAIPAAQJLAL4ogDQAAAPAAQJLAL4ogDQAAAuAAQKfzEAAg8ACQlSCQFpAJEBAA8ACQlSCQFpAJEBAAAA.Masseffex:BAABLgAECn8VAAMCAAgJzRTUIAC+AQACAAgJzRTUIAC+AQAIAAIJAw+QoQBqAAAAAA==.',
Mc='Mcshooty:BAAALgAECgYJDAAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJMgAeALIZAA==.Morganä:BAAALgAECgQJDgAAAA==.Morthrin:BAABLgAECn8VAAIIAAkJ5hRZJwATAgAIAAkJ5hRZJwATAgAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn89AAIEAAkJsByTFABwAgAEAAkJsByTFABwAgAAAA==.',
Ne='Ned:BAAALgAECgcJCAABLgAECggJDwADAAAAAA==.Negora:BAAALgAECgEJAQAAAA==.Nelaris:BAAALgADCgEJAQAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAIOAAYJ5BtXIgCLAQAOAAYJ5BtXIgCLAQAAAA==.Nightember:BAABLgAECn8iAAQYAAkJjQ8MIgDIAQAYAAkJjQ8MIgDIAQAeAAgJoRErEADFAQAiAAEJgAn4JgAuAAABLgAFFAQJDwAVAIEQAA==.Nightski:BAABLgAECn8qAAIIAAkJgBeeIAA/AgAIAAkJgBeeIAA/AgAAAA==.Nikolatesla:BAAALgAECgcJDgAAAA==.Nizzari:BAACLgAFFH8QAAIdAAUJ1Af8IAAVAQAdAAUJ1Af8IAAVAQAuAAQKf0oABB0ACQnlFSYRAB0CAB0ACQnlFSYRAB0CABwAAgkdCpEeAGYAACMAAQmUB1gmACgAAAAA.',
No='Nomas:BAAALgAECgYJBgAAAA==.Nothalyer:BAABLgAECn80AAIeAAkJ+g77EQCmAQAeAAkJ+g77EQCmAQAAAA==.',
Of='Offline:BAABLgAECn8XAAIIAAgJziGNDAD4AgAIAAgJziGNDAD4AgAAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIUAAMJcgf7iwDFAAAUAAMJcgf7iwDFAAAuAAQKfzcAAhQACQmeGjQ1AEECABQACQmeGjQ1AEECAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasithim:BAAALgAECgQJBAABLgAECggJIQALAJsTAA==.Orwasitme:BAAALgAECgcJBwABLgAECggJIQALAJsTAA==.Orwasitshrek:BAABLgAECn8hAAMLAAgJmxMPLACiAQALAAgJmxMPLACiAQAKAAEJ0Am8fQApAAAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECggJIQALAJsTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAFFAEJAQAAAA==.',
Pj='Pjxyo:BAAALgAECgUJBQAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8PAAMEAAYJzAJzNAAJAQAEAAYJzAJzNAAJAQAZAAUJZQxZKgDmAAAuAAQKfzIAAwQACQlRERlCAKEBAAQACAlSEhlCAKEBABkACQlUEzsxAHYBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECggJDwAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Ra='Ranin:BAABLgAECn8YAAIaAAgJXxUkFQDiAQAaAAgJXxUkFQDiAQAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAABLgAECn8YAAMIAAYJDBVxRgBzAQAIAAYJDBVxRgBzAQACAAEJ0wlrkQArAAABLgAFFAQJCwAVAFwaAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgYJDwAAAA==.',
Sa='Salvation:BAAALgAECgkJEgAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Satrat:BAAALgAFFAEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJBgAAAA==.Senovourer:BAABLgAECn8fAAIbAAkJjCEJCwAqAwAbAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn85AAMIAAkJsyDmBQBXAwAIAAkJsyDmBQBXAwAWAAEJggdwVgApAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAACLgAFFH8NAAIkAAQJlx0sCQBWAQAkAAQJlx0sCQBWAQAuAAQKf0QAAiQACAkWJD4EANMCACQACAkWJD4EANMCAAAA.Shazrast:BAAALgAECgUJAwAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgADCgYJBgAAAA==.Sizouze:BAABLgAECn8pAAIGAAgJDAyZLgBUAQAGAAgJDAyZLgBUAQAAAA==.',
Sk='Skeeter:BAAALgAFFAQJBAAAAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8gAAMJAAkJhRjzAwCVAgAJAAkJhRjzAwCVAgABAAMJMwLEnAB8AAAuAAQKfy8AAwkACQnrIrYGAB8DAAkACQnrIrYGAB8DAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8eAAIEAAYJ2yBTCgAbAgAEAAYJ2yBTCgAbAgAuAAQKfzcAAgQACAlHI9wNAOMCAAQACAlHI9wNAOMCAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxlmEQBMAgACAAkJbxlmEQBMAgAAAA==.',
Sp='Spicyburrito:BAAALgAECgkJDwAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAAALgAFFAEJAwAAAA==.Tarhostamir:BAABLgAECn8dAAICAAcJVxBBNABDAQACAAcJVxBBNABDAQAAAA==.Taurup:BAAALgAECgcJEAABLgAFFAUJEAAdANQHAA==.Tazz:BAABLgAECn8dAAIMAAgJUgbqhQAtAQAMAAgJUgbqhQAtAQAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgYJDQAAAA==.Thaysinga:BAAALgAFFAMJBAAAAA==.Thelandlord:BAACLgAFFH8UAAIeAAYJahVpBQChAQAeAAYJahVpBQChAQAuAAQKfxwAAx4ACAkOG9oMAGgCAB4ACAkOG9oMAGgCACIAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8jAAILAAgJ5SQsCADcAgALAAgJ5SQsCADcAgAAAA==.Thuss:BAABLgAECn8pAAIbAAkJgxraGwBqAgAbAAkJgxraGwBqAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgQJBAAAAA==.',
Tw='Twirlywhirly:BAAALgAECgcJEgAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgAECgMJAwAAAA==.',
Un='Unplug:BAAALgAECgUJDQAAAA==.',
Va='Vaelus:BAAALgADCgMJBAAAAA==.Valkyrrie:BAAALgAECgQJBAABLgAECgkJGAAeAGsNAA==.Vander:BAAALgAECgQJBAABLgAECggJHgAVABcgAA==.Vanidossa:BAABLgAECn8yAAIHAAkJyhNwFgAWAgAHAAkJyhNwFgAWAgAAAA==.Vannder:BAAALgAECgMJAwAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8LAAIHAAMJghOaIgDYAAAHAAMJghOaIgDYAAAuAAQKf1EAAwcACQm5I7ECADwDAAcACQm5I7ECADwDAAUAAQmBBEKDACYAAAAA.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAACLgAFFH8IAAIJAAMJnBMAMgCkAAAJAAMJnBMAMgCkAAAuAAQKfxYAAgkACQkCF3UoAMYBAAkACQkCF3UoAMYBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn87AAILAAkJfiS/AwArAwALAAkJfiS/AwArAwAAAA==.',
Wh='Whispyerwild:BAAALgAECgQJBAAAAA==.',
Wi='Wildfire:BAACLgAFFH8hAAIOAAcJsSDhAQAvAgAOAAcJsSDhAQAvAgAuAAQKfzsAAg4ACQntJlEAAIoDAA4ACQntJlEAAIoDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAcJIQAOALEgAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn83AAIRAAkJuyLXAgAQAwARAAkJuyLXAgAQAwAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMIAAYJhhtKQgCFAQAIAAYJhhtKQgCFAQACAAEJ1gKhowAaAAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8UAAIRAAcJYBj9CQCHAQARAAcJYBj9CQCHAQAuAAQKfyYABBEACAnjItcJAHoCABEACAnjItcJAHoCAAsABQlEFO9TAPsAAAoAAQkAAJGMAAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDQAAAA==.',
Ze='Zeuree:BAABLgAFFH8GAAIVAAIJWxHpSAB1AAAVAAIJWxHpSAB1AAABLgAFFAMJCgAFALcKAA==.Zeurie:BAABLgAFFH8KAAIFAAMJtwqFMwC4AAAFAAMJtwqFMwC4AAAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAABLgAECn8UAAIIAAcJYhHtRQB2AQAIAAcJYhHtRQB2AQAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAACLgAFFH8MAAIGAAQJqBswEABLAQAGAAQJqBswEABLAQAuAAQKfzoAAgYACQnqIkcDAFsDAAYACQnqIkcDAFsDAAAA.',
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
